module ConfirmTest exposing (suite)

{-| Coverage for confirm-dialog text resolution: a raw string passes through unchanged
(back-compat), a `$template` interpolates the pressed row's item context, and an expression
that resolves to nothing falls back to a sensible generic string (fail-closed) rather than a
blank dialog or raw directive JSON.
-}

import Dict
import Html exposing (Html)
import Json.Encode as Encode exposing (Value)
import JsonRender
import JsonRender.Render as Render
import JsonRender.Spec exposing (Spec)
import ProgramTest exposing (ProgramTest)
import Test exposing (Test, describe, test)
import Test.Html.Query as Query
import Test.Html.Selector as Selector


{-| A manifest with three confirm shapes: a raw-string confirm (toolbar), a per-row
`$template` confirm (inside a repeat, so it sees the item context), and a confirm whose
title and message are expressions that resolve to nothing.
-}
manifest : String
manifest =
    """
    { "root": "card"
    , "elements":
        { "card":
            { "type": "Stack"
            , "props": { "direction": "col", "gap": 1 }
            , "children": ["rawBtn", "list", "badBtn"]
            }
        , "rawBtn":
            { "type": "Button"
            , "props": { "label": "Raw" }
            , "on": { "press": { "action": "raw.act", "params": {}, "confirm":
                { "title": "Delete everything?", "message": "This cannot be undone." } } }
            }
        , "list":
            { "type": "Stack"
            , "props": { "direction": "col", "gap": 1 }
            , "repeat": { "statePath": "/instances", "key": "id" }
            , "children": ["rowBtn"]
            }
        , "rowBtn":
            { "type": "Button"
            , "props": { "label": "Scan" }
            , "on": { "press": { "action": "scan.start", "params": {}, "confirm":
                { "title": "Start scan", "message": { "$template": "Run a scan of ${name}?" } } } }
            }
        , "badBtn":
            { "type": "Button"
            , "props": { "label": "Bad" }
            , "on": { "press": { "action": "bad.act", "params": {}, "confirm":
                { "title": { "$state": "/missing" }, "message": { "$item": "nope" } } } }
            }
        }
    }
    """


specOf : String -> Spec
specOf raw =
    case JsonRender.decodeString raw of
        Ok spec ->
            spec

        Err _ ->
            { root = "missing", elements = Dict.empty, state = Encode.null }


state : Value
state =
    Encode.object
        [ ( "instances"
          , Encode.list identity
                [ Encode.object
                    [ ( "id", Encode.string "i-1" )
                    , ( "name", Encode.string "cs-spike-target" )
                    ]
                ]
          )
        ]


type alias Model =
    { renderer : Render.Model }


type Msg
    = RendererMsg Render.Msg


init : () -> ( Model, Cmd Msg )
init () =
    ( { renderer = Render.init }, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update (RendererMsg rmsg) model =
    let
        ( renderer, _ ) =
            Render.update rmsg model.renderer
    in
    ( { model | renderer = renderer }, Cmd.none )


view : Model -> Html Msg
view model =
    Html.map RendererMsg (Render.view [] (specOf manifest) state model.renderer)


start : ProgramTest Model Msg (Cmd Msg)
start =
    ProgramTest.createElement { init = init, update = update, view = view }
        |> ProgramTest.start ()


suite : Test
suite =
    describe "JsonRender.Render confirm text resolution"
        [ test "a raw-string confirm passes through unchanged (back-compat)" <|
            \_ ->
                start
                    |> ProgramTest.clickButton "Raw"
                    |> ProgramTest.ensureViewHas [ Selector.class "jr-confirm" ]
                    |> ProgramTest.expectViewHas
                        [ Selector.text "Delete everything?"
                        , Selector.text "This cannot be undone."
                        ]
        , test "a per-row $template confirm interpolates the row's item name" <|
            \_ ->
                start
                    |> ProgramTest.clickButton "Scan"
                    |> ProgramTest.ensureViewHas [ Selector.class "jr-confirm" ]
                    |> ProgramTest.expectViewHas [ Selector.text "Run a scan of cs-spike-target?" ]
        , test "an unresolvable confirm falls back to generic text, not blank or raw JSON" <|
            \_ ->
                start
                    |> ProgramTest.clickButton "Bad"
                    |> ProgramTest.ensureViewHas [ Selector.class "jr-confirm" ]
                    |> ProgramTest.expectViewHas
                        [ Selector.text "Confirm action"
                        , Selector.text "Are you sure you want to continue?"
                        ]
        , test "the unresolvable confirm never leaks a raw directive key" <|
            \_ ->
                start
                    |> ProgramTest.clickButton "Bad"
                    |> ProgramTest.expectView
                        (Query.hasNot [ Selector.text "$state" ])
        ]
