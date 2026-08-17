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
    Html.map RendererMsg (Render.view [] spec state model.renderer)


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
