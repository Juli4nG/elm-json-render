module ErrorKindTest exposing (suite)

{-| Coverage for `JsonRender.Spec.errorKind`, the classifier a host uses to decide WHICH
plain-language sentence a rejected manifest gets.

Every case here decodes a real manifest rather than asserting against a hand-written error string:
the point of keeping the classifier next to the decoder is that the two move together, and a test
fed its own copy of the message would not notice if they stopped.

-}

import Expect
import JsonRender
import JsonRender.Spec as Spec
import Test exposing (Test, describe, test)


{-| The `ErrorKind` of a manifest that must NOT decode. A manifest that decodes is itself a test
failure, reported as such rather than silently defaulting to one of the kinds.
-}
kindOf : String -> Result String Spec.ErrorKind
kindOf manifest =
    case JsonRender.decodeString manifest of
        Ok _ ->
            Err "expected this manifest to be rejected, but it decoded"

        Err message ->
            Ok (Spec.errorKind message)


suite : Test
suite =
    describe "JsonRender.Spec.errorKind"
        [ test "an off-catalog component type reads as version skew" <|
            \_ ->
                kindOf """{ "root": "x", "elements": { "x": { "type": "ScriptInjector", "props": {}, "children": [] } } }"""
                    |> Expect.equal (Ok Spec.UnknownCatalogSurface)
        , test "an unknown PROP key reads as version skew" <|
            \_ ->
                -- The manifest wants a Button prop this catalog has not grown yet.
                kindOf """{ "root": "b", "elements": { "b": { "type": "Button", "props": { "label": "Go", "tooltip": "Go now" }, "children": [] } } }"""
                    |> Expect.equal (Ok Spec.UnknownCatalogSurface)
        , test "an unknown icon NAME reads as version skew too" <|
            \_ ->
                -- The icon set is closed but grows, so a shape this build cannot draw is the same
                -- situation as a component type it cannot render: a newer manifest, not a broken one.
                kindOf """{ "root": "b", "elements": { "b": { "type": "Button", "props": { "label": "Go", "icon": "play" }, "children": [] } } }"""
                    |> Expect.equal (Ok Spec.UnknownCatalogSurface)
        , test "an unknown ELEMENT key reads as version skew" <|
            \_ ->
                -- `visible` is json-render surface this renderer deliberately does not implement.
                kindOf """{ "root": "t", "elements": { "t": { "type": "Text", "props": { "value": "hi" }, "visible": true, "children": [] } } }"""
                    |> Expect.equal (Ok Spec.UnknownCatalogSurface)
        , test "an unknown confirm key reads as version skew" <|
            \_ ->
                kindOf """{ "root": "b", "elements": { "b": { "type": "Button", "props": { "label": "Go" }, "on": { "press": { "action": "go", "confirm": { "title": "t", "message": "m", "tone": "danger" } } }, "children": [] } } }"""
                    |> Expect.equal (Ok Spec.UnknownCatalogSurface)
        , test "a missing required field reads as malformed" <|
            \_ ->
                -- Text without `value`: no newer catalog makes this renderable.
                kindOf """{ "root": "t", "elements": { "t": { "type": "Text", "props": {}, "children": [] } } }"""
                    |> Expect.equal (Ok Spec.Malformed)
        , test "a dangling child reference reads as malformed" <|
            \_ ->
                kindOf """{ "root": "c", "elements": { "c": { "type": "Card", "props": {}, "children": [ "ghost" ] } } }"""
                    |> Expect.equal (Ok Spec.Malformed)
        , test "a missing root reads as malformed" <|
            \_ ->
                kindOf """{ "root": "ghost", "elements": {} }"""
                    |> Expect.equal (Ok Spec.Malformed)
        , test "a body that is not JSON at all reads as malformed" <|
            \_ ->
                kindOf "not json at all"
                    |> Expect.equal (Ok Spec.Malformed)
        , test "a wrong-typed prop reads as malformed, not as skew" <|
            \_ ->
                -- The KEY is known; its value is nonsense. A newer renderer would not help, so
                -- this must not be reported as version skew.
                kindOf """{ "root": "s", "elements": { "s": { "type": "Stack", "props": { "direction": "sideways" }, "children": [] } } }"""
                    |> Expect.equal (Ok Spec.Malformed)
        , test "a marker string carried as DATA spoofs the classification" <|
            \_ ->
                -- Pinning the documented limitation, not endorsing it. `Decode.errorToString`
                -- prints the offending JSON, so a malformed manifest whose own data quotes one of
                -- the markers is read as skew. The cost is which reassuring sentence the reader
                -- gets; both kinds still refuse to render, which is the part that matters. This
                -- test exists so removing the limitation is a deliberate change with a failing
                -- test attached, rather than a silent one.
                kindOf """{ "root": "t", "elements": { "t": { "type": "Text", "props": { "value": "Unknown / off-catalog component type" }, "extra": 1 } } }"""
                    |> Expect.equal (Ok Spec.UnknownCatalogSurface)
        , test "the same manifest without the marker text classifies as malformed" <|
            \_ ->
                -- The control for the spoof above: identical shape, innocuous data.
                kindOf """{ "root": "t", "elements": { "t": { "type": "Text", "props": { "value": "hello" }, "children": "not-a-list" } } }"""
                    |> Expect.equal (Ok Spec.Malformed)
        , test "an unsupported $-directive reads as malformed, not as skew" <|
            \_ ->
                -- Arguable either way; pinned so the classification is a decision and not an
                -- accident. `$computed` is a json-render form this dialect refuses on purpose,
                -- and telling a reader to update would be misleading.
                kindOf """{ "root": "t", "elements": { "t": { "type": "Text", "props": { "value": { "$computed": "x" } }, "children": [] } } }"""
                    |> Expect.equal (Ok Spec.Malformed)
        ]
