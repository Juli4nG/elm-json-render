module RenderTest exposing (suite)

import Dict
import Expect
import Fixtures
import Html exposing (Html)
import Html.Attributes
import Json.Decode as Decode exposing (Value)
import Json.Encode as Encode
import JsonRender
import JsonRender.Render as Render
import JsonRender.Spec exposing (Spec)
import ProgramTest exposing (ProgramTest)
import Test exposing (Test, describe, test)
import Test.Html.Event as Event
import Test.Html.Query as Query
import Test.Html.Selector as Selector



-- TEST HARNESS (a Browser.element-shaped wrapper around the renderer)


type alias Model =
    { renderer : Render.Model
    , spec : Spec
    , state : Value
    , lastAction : Maybe { verb : String, params : Value }
    , stateChanges : List { path : String, value : Value }
    }


type Msg
    = RendererMsg Render.Msg
    | SetState Value


card : Spec
card =
    case JsonRender.decodeString Fixtures.cardJson of
        Ok decoded ->
            decoded

        Err _ ->
            -- A failing decode surfaces as missing-view assertions downstream.
            { root = "missing", elements = Dict.empty, state = Encode.null }


init : Value -> ( Model, Cmd Msg )
init initialState =
    ( { renderer = Render.init
      , spec = card
      , state = initialState
      , lastAction = Nothing
      , stateChanges = []
      }
    , Cmd.none
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SetState value ->
            ( { model | state = value }, Cmd.none )

        RendererMsg rmsg ->
            let
                ( renderer, effect ) =
                    Render.update rmsg model.renderer

                stepped =
                    { model | renderer = renderer }
            in
            case effect of
                Just (Render.EmitAction action) ->
                    ( { stepped | lastAction = Just action }, Cmd.none )

                Just (Render.EmitStateChange change) ->
                    ( { stepped | stateChanges = model.stateChanges ++ [ change ] }, Cmd.none )

                Nothing ->
                    ( stepped, Cmd.none )


view : Model -> Html Msg
view model =
    Html.map RendererMsg (Render.view [] model.spec model.state model.renderer)


start : Value -> ProgramTest Model Msg (Cmd Msg)
start initialState =
    ProgramTest.createElement { init = init, update = update, view = view }
        |> ProgramTest.start initialState



-- STATE FIXTURES (the renderer-facing projection)


type alias Instance =
    { id : String, name : String }


instances : List Instance
instances =
    Decode.decodeString
        (Decode.list
            (Decode.map2 Instance
                (Decode.field "id" Decode.string)
                (Decode.field "name" Decode.string)
            )
        )
        Fixtures.instancesJson
        |> Result.withDefault []


{-| Build the host projection: one `instances[i]` per fixture instance, each with the
given `scanState` and `selected = False`.
-}
stateWith : List String -> Value
stateWith scanStates =
    projection (List.map2 instanceValue instances scanStates)


{-| A single-instance projection (so a row "Scan" button is unambiguous to click).
-}
oneInstance : Value
oneInstance =
    projection [ instanceValue (Instance "i-1b2c3d4e" "api-backend-02") "idle" ]


projection : List Value -> Value
projection rows =
    Encode.object
        [ ( "selectAll", Encode.bool False )
        , ( "results", Encode.null )
        , ( "instances", Encode.list identity rows )
        ]


instanceValue : Instance -> String -> Value
instanceValue instance scanState =
    Encode.object
        [ ( "id", Encode.string instance.id )
        , ( "name", Encode.string instance.name )
        , ( "selected", Encode.bool False )
        , ( "scanState", Encode.string scanState )
        ]


allIdle : Value
allIdle =
    stateWith [ "idle", "idle", "idle", "idle" ]



-- TESTS


suite : Test
suite =
    describe "JsonRender.Render (elm-program-test)"
        [ test "renders one Badge row per instance (4 for the 4-instance fixture)" <|
            \_ ->
                start allIdle
                    |> ProgramTest.expectView
                        (Query.findAll [ Selector.class "jr-badge" ]
                            >> Query.count (Expect.equal 4)
                        )
        , test "the card title renders" <|
            \_ ->
                start allIdle
                    |> ProgramTest.expectViewHas [ Selector.text "Scan instances" ]
        , test "each instance name renders in its row" <|
            \_ ->
                start allIdle
                    |> ProgramTest.expectViewHas
                        [ Selector.text "web-frontend-01"
                        , Selector.text "postgres-primary"
                        ]
        , test "the per-row Badge reflects that row's scanState" <|
            \_ ->
                start (stateWith [ "idle", "running", "done", "queued" ])
                    |> ProgramTest.expectView
                        (\query ->
                            Expect.all
                                [ \_ -> badgeWithState "running" query |> Query.count (Expect.equal 1)
                                , \_ -> badgeWithState "done" query |> Query.count (Expect.equal 1)
                                , \_ -> badgeWithState "queued" query |> Query.count (Expect.equal 1)
                                ]
                                ()
                        )
        , test "feeding the fixture state machine advances a row idle->queued->running->done" <|
            \_ ->
                start allIdle
                    |> ProgramTest.ensureView
                        (\q -> badgeWithState "idle" q |> Query.count (Expect.equal 4))
                    |> ProgramTest.update (SetState (stateWith [ "idle", "queued", "idle", "idle" ]))
                    |> ProgramTest.ensureViewHas [ Selector.text "queued" ]
                    |> ProgramTest.update (SetState (stateWith [ "idle", "running", "idle", "idle" ]))
                    |> ProgramTest.ensureViewHas [ Selector.text "running" ]
                    |> ProgramTest.update (SetState (stateWith [ "idle", "done", "idle", "idle" ]))
                    |> ProgramTest.expectViewHas [ Selector.text "done" ]
        , test "clicking a per-row Scan, then confirming, emits startScan with the literal id" <|
            \_ ->
                start oneInstance
                    |> clickRowScan
                    |> ProgramTest.ensureViewHas [ Selector.class "jr-confirm" ]
                    |> ProgramTest.clickButton "Confirm"
                    |> ProgramTest.expectModel
                        (\model ->
                            model.lastAction
                                |> Maybe.map (\a -> ( a.verb, Encode.encode 0 a.params ))
                                |> Expect.equal
                                    (Just
                                        ( "scan.start"
                                        , "{\"targetInstanceIds\":[\"i-1b2c3d4e\"]}"
                                        )
                                    )
                        )
        , test "the per-row confirm message interpolates the instance name via $template" <|
            \_ ->
                start oneInstance
                    |> clickRowScan
                    |> ProgramTest.expectViewHas
                        [ Selector.text "Queue a scan for api-backend-02?" ]
        , test "dismissing the confirm dialog emits nothing" <|
            \_ ->
                start oneInstance
                    |> clickRowScan
                    |> ProgramTest.clickButton "Cancel"
                    |> ProgramTest.expectModel (\model -> model.lastAction |> Expect.equal Nothing)
        ]


{-| Click the per-row "Scan" button precisely. `clickButton "Scan"` is ambiguous because
"Scan selected" also contains the text "Scan"; scoping to the list container (the only
`<button>` inside it is the row's Scan button, for the single-instance fixture) is exact.
-}
clickRowScan : ProgramTest Model Msg (Cmd Msg) -> ProgramTest Model Msg (Cmd Msg)
clickRowScan =
    ProgramTest.simulateDomEvent
        (Query.find [ Selector.class "jr-stack--col" ]
            >> Query.find [ Selector.tag "button" ]
        )
        Event.click


badgeWithState : String -> Query.Single msg -> Query.Multiple msg
badgeWithState state query =
    query
        |> Query.findAll
            [ Selector.class "jr-badge"
            , Selector.attribute (Html.Attributes.attribute "data-state" state)
            ]
