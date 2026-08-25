module IconButtonTest exposing (suite)

{-| Coverage for the `Button` `icon` prop.

Three shapes of button live side by side in the shared contract fixture
`contract/fixtures/icon-button.json`:

  - no `icon` — must render byte-for-byte what it always did: `class="jr-button"`, the label as
    the only child, no SVG;
  - `icon` + a visible label — the glyph goes before the label, both are there;
  - `icon` + an empty label (statically `""`, and resolved to `""` per row) — icon-only, and the
    RENDERER supplies `aria-label` / `title`, since the manifest has no way to name a shape.

The decoder half is here too: the icon set is closed, so a name outside it is refused rather than
rendered without a glyph.

A second, local manifest (`interactionJson`) covers where `icon` meets `disabled` and the
empty-label rule, which the shared fixture cannot reach: a disabled icon-only button stays on
screen with its glyph and is inert, while an empty label with NO icon is still suppressed outright.
It also carries the icon-only press that emits with no `confirm` in the way.

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
    case JsonRender.decodeString Fixtures.iconButtonJson of
        Ok decoded ->
            decoded

        Err _ ->
            -- A failing decode surfaces as missing-view assertions downstream.
            { root = "missing", elements = Dict.empty, state = Encode.null }


{-| Two rows: the first carries a visible `openLabel`, the second resolves it to the empty
string, so one fixture covers "icon beside a label" and "icon-only because the label resolved
away" without a second manifest.
-}
state : Value
state =
    Encode.object
        [ ( "rows"
          , Encode.list identity
                [ row "r-1" "web-frontend-01" "View"
                , row "r-2" "batch-worker-07" ""
                ]
          )
        ]


row : String -> String -> String -> Value
row id name openLabel =
    Encode.object
        [ ( "id", Encode.string id )
        , ( "name", Encode.string name )
        , ( "openLabel", Encode.string openLabel )
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


{-| Buttons in document order: the three in the legend, then two per row. Positional finders
rather than text ones, because half of these buttons deliberately have no text.
-}
buttonAt : Int -> Query.Single msg -> Query.Single msg
buttonAt index =
    Query.findAll [ Selector.class "jr-button" ] >> Query.index index


plainButton : Query.Single msg -> Query.Single msg
plainButton =
    buttonAt 0


refreshButton : Query.Single msg -> Query.Single msg
refreshButton =
    buttonAt 1


closeButton : Query.Single msg -> Query.Single msg
closeButton =
    buttonAt 2


{-| The open button of the first row, whose `openLabel` resolves to `"View"`.
-}
firstRowOpen : Query.Single msg -> Query.Single msg
firstRowOpen =
    buttonAt 3


{-| The open button of the second row, whose `openLabel` resolves to `""`.
-}
secondRowOpen : Query.Single msg -> Query.Single msg
secondRowOpen =
    buttonAt 5


{-| The trash button of the second row.
-}
secondRowRemove : Query.Single msg -> Query.Single msg
secondRowRemove =
    buttonAt 6


expectAction : Maybe ( String, String ) -> ProgramTest Model Msg (Cmd Msg) -> Expect.Expectation
expectAction expected =
    ProgramTest.expectModel
        (\model ->
            model.lastAction
                |> Maybe.map (\a -> ( a.verb, Encode.encode 0 a.params ))
                |> Expect.equal expected
        )



-- INTERACTION FIXTURE


{-| A second, local manifest for where `icon` meets `disabled` and the empty-label rule.

Kept out of `contract/fixtures/icon-button.json` for two reasons: that fixture carries no
`disabled` prop, and adding buttons to it would shift every positional finder above. Both buttons
here are icon-only, and neither wires a `confirm`, which the shared fixture's icon-only button
does — so this also covers the press path that emits straight through instead of through a dialog.

-}
interactionJson : String
interactionJson =
    """
    { "root": "bar"
    , "elements":
        { "bar":
            { "type": "Stack"
            , "props": { "direction": "row", "gap": 2 }
            , "children": [ "remove", "refresh" ]
            }
        , "remove":
            { "type": "Button"
            , "props": { "label": "", "icon": "trash", "disabled": { "$state": "/requestBusy" } }
            , "on": { "press": { "action": "row.remove", "params": { "resultId": "r-2" } } }
            }
        , "refresh":
            { "type": "Button"
            , "props": { "label": "", "icon": "refresh" }
            , "on": { "press": { "action": "row.refresh", "params": {} } }
            }
        }
    }
    """


interactionSpec : Spec
interactionSpec =
    case JsonRender.decodeString interactionJson of
        Ok decoded ->
            decoded

        Err _ ->
            { root = "missing", elements = Dict.empty, state = Encode.null }


busy : Bool -> Value
busy value =
    Encode.object [ ( "requestBusy", Encode.bool value ) ]


renderInteraction : Bool -> Query.Single Render.Msg
renderInteraction requestBusy =
    Render.view Render.defaultOptions interactionSpec (busy requestBusy) Render.init
        |> Query.fromHtml


startInteraction : Bool -> ProgramTest Model Msg (Cmd Msg)
startInteraction requestBusy =
    ProgramTest.createElement
        { init = init
        , update = update
        , view =
            \model ->
                Html.map RendererMsg
                    (Render.view Render.defaultOptions interactionSpec (busy requestBusy) model.renderer)
        }
        |> ProgramTest.start ()


{-| The trash button; index 0 either way, since `disabled` never removes the element.
-}
removeButton : Query.Single msg -> Query.Single msg
removeButton =
    buttonAt 0


{-| The refresh button: icon-only, enabled, and wired to a press with no `confirm`.
-}
refreshNoConfirmButton : Query.Single msg -> Query.Single msg
refreshNoConfirmButton =
    buttonAt 1



-- TESTS


suite : Test
suite =
    describe "Button icon"
        [ describe "without an icon"
            [ test "it carries jr-button and neither icon class" <|
                \_ ->
                    start
                        |> ProgramTest.expectView
                            (plainButton
                                >> Expect.all
                                    [ Query.has [ Selector.class "jr-button", Selector.text "Scan selected" ]
                                    , Query.hasNot [ Selector.class "jr-button--icon" ]
                                    , Query.hasNot [ Selector.class "jr-button--icon-only" ]
                                    ]
                            )
            , test "the label is still the only child: no SVG" <|
                \_ ->
                    start
                        |> ProgramTest.expectView (plainButton >> Query.hasNot [ Selector.tag "svg" ])
            , test "the renderer names nothing: no aria-label, no title" <|
                \_ ->
                    start
                        |> ProgramTest.expectView
                            (plainButton
                                >> Query.hasNot
                                    [ Selector.attribute (Html.Attributes.attribute "aria-label" "Remove") ]
                            )
            ]
        , describe "with an icon and a visible label"
            [ test "it gets jr-button--icon but not jr-button--icon-only" <|
                \_ ->
                    start
                        |> ProgramTest.expectView
                            (refreshButton
                                >> Expect.all
                                    [ Query.has [ Selector.class "jr-button--icon" ]
                                    , Query.hasNot [ Selector.class "jr-button--icon-only" ]
                                    ]
                            )
            , test "the glyph is drawn inline, in currentColor, at 16px" <|
                \_ ->
                    start
                        |> ProgramTest.expectView
                            (refreshButton
                                >> Query.find [ Selector.tag "svg" ]
                                >> Query.has
                                    [ Selector.class "jr-icon"
                                    , Selector.class "jr-icon--refresh"
                                    , Selector.attribute (Html.Attributes.attribute "stroke" "currentColor")
                                    , Selector.attribute (Html.Attributes.attribute "width" "16")
                                    , Selector.attribute (Html.Attributes.attribute "aria-hidden" "true")
                                    ]
                            )
            , test "the label stays visible text" <|
                \_ ->
                    start |> ProgramTest.expectView (refreshButton >> Query.has [ Selector.text "Refresh" ])
            , test "the visible label is the accessible name: the renderer adds none" <|
                \_ ->
                    start
                        |> ProgramTest.expectView
                            (refreshButton
                                >> Query.hasNot
                                    [ Selector.attribute (Html.Attributes.attribute "aria-label" "Refresh") ]
                            )
            ]
        , describe "icon-only"
            [ test "a statically empty label renders the glyph and no text" <|
                \_ ->
                    start
                        |> ProgramTest.expectView
                            (closeButton
                                >> Expect.all
                                    [ Query.has [ Selector.class "jr-button--icon", Selector.class "jr-button--icon-only" ]
                                    , Query.find [ Selector.tag "svg" ] >> Query.has [ Selector.class "jr-icon--close" ]
                                    ]
                            )
            , test "the renderer supplies aria-label and title, per icon" <|
                \_ ->
                    start
                        |> ProgramTest.expectView
                            (closeButton
                                >> Query.has
                                    [ Selector.attribute (Html.Attributes.attribute "aria-label" "Close")
                                    , Selector.attribute (Html.Attributes.title "Close")
                                    ]
                            )
            , test "trash is named Remove" <|
                \_ ->
                    start
                        |> ProgramTest.expectView
                            (secondRowRemove
                                >> Query.has [ Selector.attribute (Html.Attributes.title "Remove") ]
                            )
            , test "a label that RESOLVES to empty is icon-only too" <|
                \_ ->
                    start
                        |> ProgramTest.expectView
                            (secondRowOpen >> Query.has [ Selector.class "jr-button--icon-only" ])
            , test "the same button in a row whose label resolves non-empty keeps its text" <|
                \_ ->
                    start
                        |> ProgramTest.expectView
                            (firstRowOpen
                                >> Expect.all
                                    [ Query.has [ Selector.class "jr-button--icon", Selector.text "View" ]
                                    , Query.hasNot [ Selector.class "jr-button--icon-only" ]
                                    ]
                            )
            ]
        , describe "an icon-only button is still a button"
            [ test "pressing it opens its confirm and emits nothing yet" <|
                \_ ->
                    start
                        |> ProgramTest.simulateDomEvent secondRowRemove Event.click
                        |> ProgramTest.ensureViewHas [ Selector.class "jr-confirm" ]
                        |> expectAction Nothing
            , test "confirming emits the pressed row's params" <|
                \_ ->
                    start
                        |> ProgramTest.simulateDomEvent secondRowRemove Event.click
                        |> ProgramTest.clickButton "Confirm"
                        |> expectAction (Just ( "row.remove", "{\"resultId\":\"/rows/1/id\"}" ))
            , test "an enabled icon-only button with no confirm emits its press straight through" <|
                \_ ->
                    -- The icon-only press above routes through a dialog, so on its own it never
                    -- exercises the direct path. Here the press IS the emit.
                    startInteraction False
                        |> ProgramTest.simulateDomEvent refreshNoConfirmButton Event.click
                        |> expectAction (Just ( "row.refresh", "{}" ))
            ]
        , describe "icon-only and disabled"
            [ test "a disabled icon-only button emits nothing, as any disabled button" <|
                \_ ->
                    renderInteraction True
                        |> removeButton
                        |> Event.simulate Event.click
                        |> Event.toResult
                        |> Expect.err
            , test "the same button emits once it is no longer disabled (guards the case above)" <|
                \_ ->
                    renderInteraction False
                        |> removeButton
                        |> Event.simulate Event.click
                        |> Event.toResult
                        |> Expect.ok
            , test "a disabled icon-only button still RENDERS: the glyph is not the empty label" <|
                \_ ->
                    -- The three rules meet here. Empty label plus icon means icon-only, not
                    -- suppressed; disabled means unavailable, not absent. So the control stays on
                    -- screen, keeps its glyph and its renderer-supplied name, and is inert.
                    renderInteraction True
                        |> removeButton
                        |> Expect.all
                            [ Query.has
                                [ Selector.class "jr-button--icon-only"
                                , Selector.class "jr-button--disabled"
                                , Selector.attribute (Html.Attributes.disabled True)
                                , Selector.attribute (Html.Attributes.title "Remove")
                                ]
                            , Query.find [ Selector.tag "svg" ]
                                >> Query.has [ Selector.class "jr-icon--trash" ]
                            ]
            , test "an empty label with no icon is still suppressed, disabled or not" <|
                \_ ->
                    -- The exemption is the icon's, not `disabled`'s.
                    JsonRender.decodeString
                        """
                        { "root": "b"
                        , "elements":
                            { "b":
                                { "type": "Button"
                                , "props": { "label": "", "disabled": true }
                                , "on": { "press": { "action": "row.remove", "params": {} } }
                                }
                            }
                        }
                        """
                        |> Result.map
                            (\s ->
                                Render.view Render.defaultOptions s Encode.null Render.init
                                    |> Query.fromHtml
                                    |> Query.findAll [ Selector.tag "button" ]
                                    |> Query.count (Expect.equal 0)
                            )
                        |> Result.withDefault (Expect.fail "the manifest should have decoded")
            ]
        , describe "decode"
            [ test "the contract fixture decodes" <|
                \_ ->
                    JsonRender.decodeString Fixtures.iconButtonJson
                        |> Result.map (always "ok")
                        |> Expect.equal (Ok "ok")
            , test "an icon outside the closed set is refused" <|
                \_ ->
                    JsonRender.decodeString (buttonWith "\"icon\": \"skull\"")
                        |> Result.mapError (always "refused")
                        |> Expect.equal (Err "refused")
            , test "a non-string icon is refused" <|
                \_ ->
                    JsonRender.decodeString (buttonWith "\"icon\": true")
                        |> Result.mapError (always "refused")
                        |> Expect.equal (Err "refused")
            , test "an explicit null icon is refused, not read as absent" <|
                \_ ->
                    JsonRender.decodeString (buttonWith "\"icon\": null")
                        |> Result.mapError (always "refused")
                        |> Expect.equal (Err "refused")
            , test "a known icon decodes" <|
                \_ ->
                    JsonRender.decodeString (buttonWith "\"icon\": \"trash\"")
                        |> Result.map (always "ok")
                        |> Expect.equal (Ok "ok")
            , test "icon is a Button prop only: it is refused on a Text" <|
                \_ ->
                    JsonRender.decodeString
                        """
                        { "root": "t"
                        , "elements": { "t": { "type": "Text", "props": { "value": "hi", "icon": "trash" } } }
                        }
                        """
                        |> Result.mapError (always "refused")
                        |> Expect.equal (Err "refused")
            ]
        ]


{-| A one-button manifest with the given `icon` entry spliced into its props.
-}
buttonWith : String -> String
buttonWith iconEntry =
    """
    { "root": "b"
    , "elements": { "b": { "type": "Button", "props": { "label": "Go", """ ++ iconEntry ++ """ } } }
    }
    """
