module Main exposing (main)

{-| Demo host for the native Elm json-render renderer.

This is a small **host**: it owns the json-render `state`, projects it for the renderer
(`contract/host-renderer-interface.md`), handles the renderer's `Effect`s (start scans,
apply checkbox write-backs), and drives the fixture scan state machine
(`contract/fixtures/state-machine.md`) off a wall clock.

Two scenarios (via the `scenario` flag from `index.html`):

  - `"live"` — start all rows idle; user clicks Scan / Select all and a 250 ms tick
    advances each triggered row queued → running → done (the scripted row errors).
  - `"final"` — jump straight to the deterministic terminal state (all rows scanned,
    `batch-worker-07` in error, all selected). Used by the Playwright conformance
    snapshot so the captured HTML is stable.

-}

import Browser
import Dict exposing (Dict)
import Fixtures
import Html exposing (Html)
import Html.Attributes as Attr
import Json.Decode as Decode exposing (Value)
import Json.Encode as Encode
import JsonRender
import JsonRender.Render as Render
import JsonRender.Spec exposing (Spec)
import Set exposing (Set)
import Time



-- TIMELINE (contract/fixtures/state-machine.md)


queuedToRunningMs : Float
queuedToRunningMs =
    1000


runningToDoneMs : Float
runningToDoneMs =
    4000


tickMs : Float
tickMs =
    250


{-| The one instance scripted to take the error branch at t+4s.
-}
erroringId : String
erroringId =
    "i-3d4e5f6a"



-- MODEL


type alias Instance =
    { id : String, name : String }


type Scenario
    = Live
    | Final


type alias Model =
    { renderer : Render.Model
    , spec : Spec
    , instances : List Instance
    , selection : Set String
    , selectAll : Bool
    , startedAt : Dict String Float
    , now : Float
    , scenario : Scenario
    }


type Msg
    = RendererMsg Render.Msg
    | Tick Time.Posix


main : Program Value Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


init : Value -> ( Model, Cmd Msg )
init flags =
    let
        scenario =
            case Decode.decodeValue (Decode.field "scenario" Decode.string) flags of
                Ok "final" ->
                    Final

                _ ->
                    Live

        instances =
            Decode.decodeString instancesDecoder Fixtures.instancesJson
                |> Result.withDefault []

        base =
            { renderer = Render.init
            , spec = card
            , instances = instances
            , selection = Set.empty
            , selectAll = False
            , startedAt = Dict.empty
            , now = 0
            , scenario = scenario
            }
    in
    ( case scenario of
        Final ->
            toFinal base

        Live ->
            base
    , Cmd.none
    )


{-| The deterministic terminal state: every row scanned long ago (so all are done /
error), every row selected.
-}
toFinal : Model -> Model
toFinal model =
    { model
        | now = 100000
        , startedAt = model.instances |> List.map (\i -> ( i.id, 0 )) |> Dict.fromList
        , selection = model.instances |> List.map .id |> Set.fromList
        , selectAll = True
    }


card : Spec
card =
    case JsonRender.decodeString Fixtures.cardJson of
        Ok spec ->
            spec

        Err _ ->
            { root = "missing", elements = Dict.empty, state = Encode.null }


instancesDecoder : Decode.Decoder (List Instance)
instancesDecoder =
    Decode.list
        (Decode.map2 Instance
            (Decode.field "id" Decode.string)
            (Decode.field "name" Decode.string)
        )



-- THE SCAN STATE MACHINE


scanStateOf : Model -> String -> String
scanStateOf model id =
    case Dict.get id model.startedAt of
        Nothing ->
            "idle"

        Just started ->
            let
                elapsed =
                    model.now - started
            in
            if elapsed < queuedToRunningMs then
                "queued"

            else if elapsed < runningToDoneMs then
                "running"

            else if id == erroringId then
                "error"

            else
                "done"


isActive : String -> Bool
isActive state =
    state == "queued" || state == "running"



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Tick _ ->
            ( { model | now = model.now + tickMs }, Cmd.none )

        RendererMsg rmsg ->
            let
                ( renderer, effect ) =
                    Render.update rmsg model.renderer

                stepped =
                    { model | renderer = renderer }
            in
            ( applyEffect effect stepped, Cmd.none )


applyEffect : Maybe Render.Effect -> Model -> Model
applyEffect effect model =
    case effect of
        Nothing ->
            model

        Just (Render.EmitAction action) ->
            if action.verb == "cloudshield.startScan" then
                startScan (targetsOf model action.params) model

            else
                -- Off-allowlist verb: a real host would reject; the demo ignores it.
                model

        Just (Render.EmitStateChange change) ->
            applyStateChange change model


{-| Resolve the `targetInstanceIds` param: an empty array means "use current selection"
(the pinned host convention), else the explicit ids.
-}
targetsOf : Model -> Value -> List String
targetsOf model params =
    case Decode.decodeValue (Decode.field "targetInstanceIds" (Decode.list Decode.string)) params of
        Ok [] ->
            Set.toList model.selection

        Ok ids ->
            ids

        Err _ ->
            []


{-| Start each target whose row is idle/done/error; rows already queued/running are
skipped (dedup), each on its own t=0 clock.
-}
startScan : List String -> Model -> Model
startScan ids model =
    let
        trigger id startedAt =
            if isActive (scanStateOf model id) then
                startedAt

            else
                Dict.insert id model.now startedAt
    in
    { model | startedAt = List.foldl trigger model.startedAt ids }


applyStateChange : { path : String, value : Value } -> Model -> Model
applyStateChange change model =
    let
        bool =
            Decode.decodeValue Decode.bool change.value |> Result.withDefault False
    in
    case String.split "/" change.path of
        [ "", "selectAll" ] ->
            { model
                | selectAll = bool
                , selection =
                    if bool then
                        model.instances |> List.map .id |> Set.fromList

                    else
                        Set.empty
            }

        [ "", "instances", indexStr, "selected" ] ->
            case String.toInt indexStr |> Maybe.andThen (instanceIdAt model) of
                Just id ->
                    let
                        selection =
                            if bool then
                                Set.insert id model.selection

                            else
                                Set.remove id model.selection
                    in
                    { model
                        | selection = selection
                        , selectAll = Set.size selection == List.length model.instances
                    }

                Nothing ->
                    model

        _ ->
            model


instanceIdAt : Model -> Int -> Maybe String
instanceIdAt model index =
    model.instances |> List.drop index |> List.head |> Maybe.map .id



-- THE RENDERER-FACING PROJECTION (contract/host-renderer-interface.md §1.2)


projection : Model -> Value
projection model =
    Encode.object
        [ ( "selectAll", Encode.bool model.selectAll )
        , ( "results", Encode.null )
        , ( "instances", Encode.list (instanceProjection model) model.instances )
        ]


instanceProjection : Model -> Instance -> Value
instanceProjection model instance =
    Encode.object
        [ ( "id", Encode.string instance.id )
        , ( "name", Encode.string instance.name )
        , ( "selected", Encode.bool (Set.member instance.id model.selection) )
        , ( "scanState", Encode.string (scanStateOf model instance.id) )
        ]



-- VIEW / SUBSCRIPTIONS


view : Model -> Html Msg
view model =
    Html.div [ Attr.class "demo" ]
        [ Html.map RendererMsg (Render.view model.spec (projection model) model.renderer) ]


subscriptions : Model -> Sub Msg
subscriptions model =
    case model.scenario of
        Final ->
            Sub.none

        Live ->
            if List.any (scanStateOf model >> isActive) (List.map .id model.instances) then
                Time.every tickMs Tick

            else
                Sub.none
