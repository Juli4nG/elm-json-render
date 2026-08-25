module PressableTest exposing (suite)

{-| Coverage for press bindings on non-`Button` elements (`Text`, `Badge`, `Stack`).

An element carrying `on.press` becomes a button for assistive tech and the keyboard:
`role="button"`, `tabindex="0"`, the `jr-pressable` styling hook, click, and Enter/Space.
An element with no binding must be byte-for-byte what it always was: no class, no role,
no tabindex, no handlers. Both halves are asserted here against the shared contract
fixture `contract/fixtures/pressable.json`.

-}

import Dict
import Expect
import Fixtures
import Html exposing (Html)
import Html.Attributes
import Json.Encode as Encode exposing (Value)
import JsonRender
import JsonRender.Render as Render
import JsonRender.Spec exposing (Spec)
import ProgramTest exposing (ProgramTest)
import Test exposing (Test, describe, test)
import Test.Html.Event as Event
import Test.Html.Query as Query
import Test.Html.Selector as Selector



-- HARNESS


type alias Model =
    { renderer : Render.Model
    , lastAction : Maybe { verb : String, params : Value }
    }


type Msg
    = RendererMsg Render.Msg


spec : Spec
spec =
    case JsonRender.decodeString Fixtures.pressableJson of
        Ok decoded ->
            decoded

        Err _ ->
            -- A failing decode surfaces as missing-view assertions downstream.
            { root = "missing", elements = Dict.empty, state = Encode.null }


{-| Two rows, so `$item` resolution is unambiguous per row and the second row carries the
error text the Badge press hands back.
-}
state : Value
state =
    Encode.object
        [ ( "rows"
          , Encode.list identity
                [ row "r-1" "web-frontend-01" "i-1b2c3d4e" "done" ""
                , row "r-2" "batch-worker-07" "i-7f8e9d0c" "error" "snapshot timed out"
                ]
          )
        ]


row : String -> String -> String -> String -> String -> Value
row id name instanceId rowState error =
    Encode.object
        [ ( "id", Encode.string id )
        , ( "name", Encode.string name )
        , ( "instanceId", Encode.string instanceId )
        , ( "state", Encode.string rowState )
        , ( "error", Encode.string error )
        ]


init : () -> ( Model, Cmd Msg )
init () =
    ( { renderer = Render.init, lastAction = Nothing }, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update (RendererMsg rmsg) model =
    let
        ( renderer, effect ) =
            Render.update rmsg model.renderer

        stepped =
            { model | renderer = renderer }
    in
    case effect of
        Just (Render.EmitAction action) ->
            ( { stepped | lastAction = Just action }, Cmd.none )

        Just (Render.EmitStateChange _) ->
            ( stepped, Cmd.none )

        Nothing ->
            ( stepped, Cmd.none )


view : Model -> Html Msg
view model =
    Html.map RendererMsg (Render.view Render.defaultOptions spec state model.renderer)


start : ProgramTest Model Msg (Cmd Msg)
start =
    ProgramTest.createElement { init = init, update = update, view = view }
        |> ProgramTest.start ()



-- FINDERS


{-| The pressable `Text` of the first row (the legend `Text` is not pressable, so scoping
to `jr-pressable` picks the row out).
-}
firstRowName : Query.Single msg -> Query.Single msg
firstRowName =
    Query.findAll [ Selector.class "jr-text", Selector.class "jr-pressable" ]
        >> Query.index 0


secondRowStatus : Query.Single msg -> Query.Single msg
secondRowStatus =
    Query.findAll [ Selector.class "jr-badge", Selector.class "jr-pressable" ]
        >> Query.index 1


firstRowStack : Query.Single msg -> Query.Single msg
firstRowStack =
    Query.findAll [ Selector.class "jr-stack", Selector.class "jr-pressable" ]
        >> Query.index 0


keydown : String -> ( String, Value )
keydown key =
    Event.custom "keydown" (Encode.object [ ( "key", Encode.string key ) ])


expectAction : Maybe ( String, String ) -> ProgramTest Model Msg (Cmd Msg) -> Expect.Expectation
expectAction expected =
    ProgramTest.expectModel
        (\model ->
            model.lastAction
                |> Maybe.map (\a -> ( a.verb, Encode.encode 0 a.params ))
                |> Expect.equal expected
        )


buttonAttributes : List Selector.Selector
buttonAttributes =
    [ Selector.class "jr-pressable"
    , Selector.attribute (Html.Attributes.attribute "role" "button")
    , Selector.attribute (Html.Attributes.tabindex 0)
    ]



-- TESTS


suite : Test
suite =
    describe "press bindings on Text / Badge / Stack"
        [ describe "with a binding"
            [ test "the row Text gets role, tabindex and jr-pressable" <|
                \_ ->
                    start |> ProgramTest.expectView (firstRowName >> Query.has buttonAttributes)
            , test "the row Badge gets role, tabindex and jr-pressable" <|
                \_ ->
                    start |> ProgramTest.expectView (secondRowStatus >> Query.has buttonAttributes)
            , test "the row Stack gets role, tabindex and jr-pressable" <|
                \_ ->
                    start |> ProgramTest.expectView (firstRowStack >> Query.has buttonAttributes)
            , test "a Badge keeps its own class and data-state alongside jr-pressable" <|
                \_ ->
                    start
                        |> ProgramTest.expectView
                            (secondRowStatus
                                >> Query.has
                                    [ Selector.class "jr-badge"
                                    , Selector.class "jr-badge--danger"
                                    , Selector.class "jr-pressable"
                                    , Selector.attribute (Html.Attributes.attribute "data-state" "error")
                                    ]
                            )
            , test "a Stack keeps its direction class and data-gap alongside jr-pressable" <|
                \_ ->
                    start
                        |> ProgramTest.expectView
                            (firstRowStack
                                >> Query.has
                                    [ Selector.class "jr-stack--row"
                                    , Selector.class "jr-pressable"
                                    , Selector.attribute (Html.Attributes.attribute "data-gap" "2")
                                    ]
                            )
            ]
        , describe "without a binding (unchanged rendering)"
            [ test "the legend Text has no jr-pressable, role or tabindex" <|
                \_ ->
                    start
                        |> ProgramTest.expectView
                            (Query.find [ Selector.class "jr-text", Selector.text "Recent scans" ]
                                >> Query.hasNot buttonAttributes
                            )
            , test "the legend Badge has no jr-pressable, role or tabindex" <|
                \_ ->
                    start
                        |> ProgramTest.expectView
                            (Query.find [ Selector.class "jr-badge", Selector.text "idle" ]
                                >> Query.hasNot buttonAttributes
                            )
            , test "the legend Stack has no jr-pressable, role or tabindex" <|
                \_ ->
                    start
                        |> ProgramTest.expectView
                            (Query.find [ Selector.class "jr-stack--row" ]
                                >> Query.hasNot buttonAttributes
                            )
            , test "a non-pressable Text has no click handler at all" <|
                \_ ->
                    Query.fromHtml (view { renderer = Render.init, lastAction = Nothing })
                        |> Query.find [ Selector.class "jr-text", Selector.text "Recent scans" ]
                        |> Event.simulate Event.click
                        |> Event.toResult
                        |> Result.map (always "handled")
                        |> Expect.err
            ]
        , describe "click"
            [ test "clicking a pressable Text emits its action with resolved params" <|
                \_ ->
                    start
                        |> ProgramTest.simulateDomEvent firstRowName Event.click
                        |> expectAction
                            (Just ( "row.navigate", "{\"instanceId\":\"/rows/0/instanceId\"}" ))
            , test "clicking a pressable Stack emits the row action for that row" <|
                \_ ->
                    start
                        |> ProgramTest.simulateDomEvent firstRowStack Event.click
                        |> expectAction (Just ( "row.open", "{\"resultId\":\"/rows/0/id\"}" ))
            , test "a press carrying a confirm opens the dialog and emits nothing yet" <|
                \_ ->
                    start
                        |> ProgramTest.simulateDomEvent secondRowStatus Event.click
                        |> ProgramTest.ensureViewHas [ Selector.class "jr-confirm" ]
                        |> expectAction Nothing
            , test "confirming a pressable Badge emits with the pressed row's context" <|
                \_ ->
                    start
                        |> ProgramTest.simulateDomEvent secondRowStatus Event.click
                        |> ProgramTest.ensureViewHas
                            [ Selector.text "Open the error reported for batch-worker-07." ]
                        |> ProgramTest.clickButton "Confirm"
                        |> expectAction (Just ( "row.detail", "{\"text\":\"/rows/1/error\"}" ))
            ]
        , describe "keyboard"
            [ test "Enter on a pressable Text emits the same action as a click" <|
                \_ ->
                    start
                        |> ProgramTest.simulateDomEvent firstRowName (keydown "Enter")
                        |> expectAction
                            (Just ( "row.navigate", "{\"instanceId\":\"/rows/0/instanceId\"}" ))
            , test "Space on a pressable Stack emits the same action as a click" <|
                \_ ->
                    start
                        |> ProgramTest.simulateDomEvent firstRowStack (keydown " ")
                        |> expectAction (Just ( "row.open", "{\"resultId\":\"/rows/0/id\"}" ))
            , test "the legacy Spacebar key name also emits" <|
                \_ ->
                    start
                        |> ProgramTest.simulateDomEvent firstRowStack (keydown "Spacebar")
                        |> expectAction (Just ( "row.open", "{\"resultId\":\"/rows/0/id\"}" ))
            , test "Enter on a pressable Badge with a confirm opens the dialog, emits nothing" <|
                \_ ->
                    start
                        |> ProgramTest.simulateDomEvent secondRowStatus (keydown "Enter")
                        |> ProgramTest.ensureViewHas [ Selector.class "jr-confirm" ]
                        |> expectAction Nothing
            , test "an unrelated key is ignored: the decoder fails, nothing is emitted" <|
                \_ ->
                    Query.fromHtml (view { renderer = Render.init, lastAction = Nothing })
                        |> firstRowName
                        |> Event.simulate (keydown "a")
                        |> Event.toResult
                        |> Result.map (always "handled")
                        |> Expect.err
            , test "Tab is ignored too (it must keep moving focus)" <|
                \_ ->
                    Query.fromHtml (view { renderer = Render.init, lastAction = Nothing })
                        |> firstRowStack
                        |> Event.simulate (keydown "Tab")
                        |> Event.toResult
                        |> Result.map (always "handled")
                        |> Expect.err
            , test "a non-pressable element has no keydown handler" <|
                \_ ->
                    Query.fromHtml (view { renderer = Render.init, lastAction = Nothing })
                        |> Query.find [ Selector.class "jr-badge", Selector.text "idle" ]
                        |> Event.simulate (keydown "Enter")
                        |> Event.toResult
                        |> Result.map (always "handled")
                        |> Expect.err
            ]
        , describe "decode"
            [ test "on.press decodes on Text, Badge and Stack (not Button-only)" <|
                \_ ->
                    JsonRender.decodeString Fixtures.pressableJson
                        |> Result.map (.elements >> Dict.keys)
                        |> Expect.equal
                            (Ok
                                [ "card"
                                , "legend"
                                , "legend-badge"
                                , "legend-text"
                                , "list"
                                , "row"
                                , "row-name"
                                , "row-status"
                                ]
                            )
            ]
        ]
