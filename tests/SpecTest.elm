module SpecTest exposing (suite)

import Dict
import Expect
import Fixtures
import JsonRender
import JsonRender.Spec as Spec exposing (ComponentType(..), Props(..))
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "JsonRender.Spec (fail-closed decoder)"
        [ describe "the pinned card.json"
            [ test "decodes successfully" <|
                \_ ->
                    JsonRender.decodeString Fixtures.cardJson
                        |> Result.map .root
                        |> Expect.equal (Ok "card")
            , test "has all 11 elements in the flat map" <|
                \_ ->
                    JsonRender.decodeString Fixtures.cardJson
                        |> Result.map (.elements >> Dict.size)
                        |> Expect.equal (Ok 11)
            , test "the list element carries a repeat over /instances" <|
                \_ ->
                    JsonRender.decodeString Fixtures.cardJson
                        |> Result.toMaybe
                        |> Maybe.andThen (\spec -> Dict.get "list" spec.elements)
                        |> Maybe.andThen .repeat
                        |> Maybe.map .statePath
                        |> Expect.equal (Just "/instances")
            , test "row-status decodes as a Badge bound to $item scanState" <|
                \_ ->
                    JsonRender.decodeString Fixtures.cardJson
                        |> Result.toMaybe
                        |> Maybe.andThen (\spec -> Dict.get "row-status" spec.elements)
                        |> Maybe.map .componentType
                        |> Expect.equal (Just Badge)
            ]
        , describe "fail-closed rejections"
            [ test "an off-catalog component type fails the decode" <|
                \_ ->
                    JsonRender.decodeString offCatalogType
                        |> isErr
                        |> Expect.equal True
            , test "a dangling child key fails the decode" <|
                \_ ->
                    JsonRender.decodeString danglingChild
                        |> isErr
                        |> Expect.equal True
            , test "a missing root fails the decode" <|
                \_ ->
                    JsonRender.decodeString missingRoot
                        |> isErr
                        |> Expect.equal True
            , test "a repeat without children fails the decode" <|
                \_ ->
                    JsonRender.decodeString repeatNoChildren
                        |> isErr
                        |> Expect.equal True
            , test "a Text missing its required value prop fails the decode" <|
                \_ ->
                    JsonRender.decodeString textMissingValue
                        |> isErr
                        |> Expect.equal True
            , test "an unsupported $-directive in a prop fails the decode" <|
                \_ ->
                    JsonRender.decodeString propWithUnsupportedDirective
                        |> isErr
                        |> Expect.equal True
            , test "an element-level `visible` sibling fails the decode (unsupported)" <|
                \_ ->
                    JsonRender.decodeString elementWithVisible
                        |> isErr
                        |> Expect.equal True
            , test "an unsupported $-directive nested in action params fails the decode" <|
                \_ ->
                    JsonRender.decodeString paramsWithBadDirective
                        |> isErr
                        |> Expect.equal True
            , test "a malformed $item (non-string) in action params fails the decode" <|
                \_ ->
                    JsonRender.decodeString paramsWithMalformedItem
                        |> isErr
                        |> Expect.equal True
            ]
        ]


elementWithVisible : String
elementWithVisible =
    """
    { "root": "r"
    , "elements":
        { "r": { "type": "Button", "props": { "label": "x" }, "visible": false, "children": [] } }
    }
    """


paramsWithBadDirective : String
paramsWithBadDirective =
    """
    { "root": "r"
    , "elements":
        { "r":
            { "type": "Button", "props": { "label": "x" }, "children": []
            , "on": { "press": { "action": "go", "params": { "ids": [ { "$cond": true } ] } } }
            }
        }
    }
    """


paramsWithMalformedItem : String
paramsWithMalformedItem =
    """
    { "root": "r"
    , "elements":
        { "r":
            { "type": "Button", "props": { "label": "x" }, "children": []
            , "on": { "press": { "action": "go", "params": { "ids": [ { "$item": 123 } ] } } }
            }
        }
    }
    """


offCatalogType : String
offCatalogType =
    """
    { "root": "r"
    , "elements": { "r": { "type": "ScriptInjector", "props": {}, "children": [] } }
    }
    """


danglingChild : String
danglingChild =
    """
    { "root": "r"
    , "elements": { "r": { "type": "Card", "props": {}, "children": ["ghost"] } }
    }
    """


missingRoot : String
missingRoot =
    """
    { "root": "nope"
    , "elements": { "r": { "type": "Card", "props": {}, "children": [] } }
    }
    """


repeatNoChildren : String
repeatNoChildren =
    """
    { "root": "r"
    , "elements": { "r": { "type": "Stack", "props": {}, "repeat": { "statePath": "/xs" }, "children": [] } }
    }
    """


textMissingValue : String
textMissingValue =
    """
    { "root": "r"
    , "elements": { "r": { "type": "Text", "props": {}, "children": [] } }
    }
    """


propWithUnsupportedDirective : String
propWithUnsupportedDirective =
    """
    { "root": "r"
    , "elements": { "r": { "type": "Text", "props": { "value": { "$computed": "evil" } }, "children": [] } }
    }
    """


isErr : Result e a -> Bool
isErr result =
    case result of
        Err _ ->
            True

        Ok _ ->
            False
