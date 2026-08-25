module ButtonDisabledTest exposing (emptyLabelSuite, suite)

{-| Coverage for the Button `disabled` prop and the empty-label exclusion.

The `disabled` rule: an optional expression that, when it resolves truthy, renders the button inert
three ways over — the native `disabled` attribute, a `jr-button--disabled` class, and no press
handler. Only the last is enforcement; the other two are presentation, so the emitted-message
assertions are the ones that matter here.

The empty-label rule: an empty resolved `label` renders no button at all. The catalog refuses an
element-level `visible` prop, so collapsing the label to `""` is the only way a manifest can say
"this action does not apply to this row". Emitting a `<button>` anyway put an invisible control
with a live press handler on every such row, and the empty-label row is precisely the one whose
press carries no id. An `icon` is the one exception: a glyph is visible and meaningful with no
text, so `label: ""` + `icon` renders icon-only (covered in `IconButtonTest`).

-}

import Dict
import Expect
import Html.Attributes
import Json.Encode as Encode
import JsonRender
import JsonRender.Render as Render
import JsonRender.Spec exposing (Spec)
import Test exposing (Test, describe, test)
import Test.Html.Event as Event
import Test.Html.Query as Query
import Test.Html.Selector as Selector


specOf : String -> Spec
specOf raw =
    case JsonRender.decodeString raw of
        Ok spec ->
            spec

        Err _ ->
            { root = "missing", elements = Dict.empty, state = Encode.null }


render : String -> Encode.Value -> Query.Single Render.Msg
render raw state =
    Render.view Render.defaultOptions (specOf raw) state Render.init
        |> Query.fromHtml


withDisabled : String
withDisabled =
    """
    { "root": "b"
    , "elements":
        { "b":
            { "type": "Button"
            , "props": { "label": "View", "disabled": { "$state": "/busy" } }
            , "on": { "press": { "action": "openSession", "params": {} } }
            , "children": []
            }
        }
    }
    """


withoutDisabled : String
withoutDisabled =
    """
    { "root": "b"
    , "elements":
        { "b":
            { "type": "Button"
            , "props": { "label": "View" }
            , "on": { "press": { "action": "openSession", "params": {} } }
            , "children": []
            }
        }
    }
    """


unknownProp : String
unknownProp =
    """
    { "root": "b"
    , "elements":
        { "b": { "type": "Button", "props": { "label": "View", "visible": true }, "children": [] } }
    }
    """


busy : Bool -> Encode.Value
busy value =
    Encode.object [ ( "busy", Encode.bool value ) ]


suite : Test
suite =
    describe "JsonRender.Render Button disabled"
        [ test "a truthy disabled renders the native disabled attribute, label intact" <|
            \_ ->
                render withDisabled (busy True)
                    |> Query.has
                        [ Selector.attribute (Html.Attributes.disabled True)
                        , Selector.text "View"
                        ]
        , test "a truthy disabled adds the jr-button--disabled styling hook" <|
            \_ ->
                render withDisabled (busy True)
                    |> Query.has [ Selector.class "jr-button--disabled" ]
        , test "a false disabled leaves the button enabled and unhooked" <|
            \_ ->
                render withDisabled (busy False)
                    |> Expect.all
                        [ Query.hasNot [ Selector.attribute (Html.Attributes.disabled True) ]
                        , Query.hasNot [ Selector.class "jr-button--disabled" ]
                        ]
        , test "a disabled button emits NO press message (the guard is real, not just styling)" <|
            \_ ->
                render withDisabled (busy True)
                    |> Query.find [ Selector.tag "button" ]
                    |> Event.simulate Event.click
                    |> Event.toResult
                    |> Expect.err
        , test "the same button emits its press once it is no longer disabled" <|
            \_ ->
                render withDisabled (busy False)
                    |> Query.find [ Selector.tag "button" ]
                    |> Event.simulate Event.click
                    |> Event.toResult
                    |> Expect.ok
        , test "a missing disabled path is falsy, so the button stays live" <|
            \_ ->
                render withDisabled Encode.null
                    |> Query.find [ Selector.tag "button" ]
                    |> Event.simulate Event.click
                    |> Event.toResult
                    |> Expect.ok
        , test "an absent disabled keeps the historical enabled button" <|
            \_ ->
                render withoutDisabled Encode.null
                    |> Query.find [ Selector.tag "button" ]
                    |> Event.simulate Event.click
                    |> Event.toResult
                    |> Expect.ok
        , test "every OTHER unknown Button prop still fails the decode (fail-closed)" <|
            \_ ->
                case JsonRender.decodeString unknownProp of
                    Ok _ ->
                        Expect.fail "a Button carrying `visible` must still be rejected"

                    Err _ ->
                        Expect.pass
        , test "a malformed disabled expression fails the decode (fail-closed)" <|
            \_ ->
                JsonRender.decodeString
                    """
                    { "root": "b"
                    , "elements":
                        { "b": { "type": "Button", "props": { "label": "x", "disabled": { "$computed": "evil" } }, "children": [] } }
                    }
                    """
                    |> Result.map (always "accepted")
                    |> Expect.err
        ]


emptyLabelSuite : Test
emptyLabelSuite =
    let
        -- A label that is a per-row `$cond`, the shape every "not applicable here" control takes.
        conditionalLabel =
            """
            { "root": "b"
            , "elements":
                { "b":
                    { "type": "Button"
                    , "props":
                        { "label": { "$cond": { "$state": "/cancellable" }, "$then": "Cancel", "$else": "" }
                        , "disabled": { "$state": "/busy" }
                        }
                    , "on": { "press": { "action": "cancelRequest", "params": {} } }
                    , "children": []
                    }
                }
            }
            """

        state cancellable requestBusy =
            Encode.object
                [ ( "cancellable", Encode.bool cancellable )
                , ( "busy", Encode.bool requestBusy )
                ]
    in
    describe "JsonRender.Render Button with an empty label"
        [ test "an empty resolved label renders no button element at all" <|
            \_ ->
                render conditionalLabel (state False False)
                    |> Query.hasNot [ Selector.tag "button" ]
        , test "and therefore emits no press — the phantom-clickable fix" <|
            \_ ->
                render conditionalLabel (state False False)
                    |> Query.findAll [ Selector.tag "button" ]
                    |> Query.count (Expect.equal 0)
        , test "a non-empty label still renders and still emits" <|
            \_ ->
                render conditionalLabel (state True False)
                    |> Query.find [ Selector.tag "button" ]
                    |> Event.simulate Event.click
                    |> Event.toResult
                    |> Expect.ok
        , test "a DISABLED non-empty button still renders — this rule does not swallow it" <|
            \_ ->
                -- Disabled means "here but unavailable" and must stay visible where the eye expects
                -- it; empty-label means "not applicable" and goes away. Two different states.
                render conditionalLabel (state True True)
                    |> Query.has
                        [ Selector.tag "button"
                        , Selector.attribute (Html.Attributes.disabled True)
                        , Selector.text "Cancel"
                        ]
        , test "a literal empty label is excluded too, not only a collapsed $cond" <|
            \_ ->
                render
                    """
                    { "root": "b"
                    , "elements":
                        { "b":
                            { "type": "Button"
                            , "props": { "label": "" }
                            , "on": { "press": { "action": "openSession", "params": {} } }
                            , "children": []
                            }
                        }
                    }
                    """
                    Encode.null
                    |> Query.hasNot [ Selector.tag "button" ]
        ]
