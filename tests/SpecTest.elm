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
            , test "a Badge with no variant decodes with variant = Nothing" <|
                \_ ->
                    JsonRender.decodeString Fixtures.cardJson
                        |> Result.toMaybe
                        |> Maybe.andThen (\spec -> Dict.get "row-status" spec.elements)
                        |> Maybe.andThen badgeVariantPresent
                        |> Expect.equal (Just False)
            ]
        , describe "the Badge variant prop"
            [ test "a Badge with a variant expression decodes (variant present)" <|
                \_ ->
                    JsonRender.decodeString badgeWithVariant
                        |> Result.toMaybe
                        |> Maybe.andThen (\spec -> Dict.get "r" spec.elements)
                        |> Maybe.andThen badgeVariantPresent
                        |> Expect.equal (Just True)
            , test "a Badge without a variant decodes (variant absent)" <|
                \_ ->
                    JsonRender.decodeString badgeWithoutVariant
                        |> Result.toMaybe
                        |> Maybe.andThen (\spec -> Dict.get "r" spec.elements)
                        |> Maybe.andThen badgeVariantPresent
                        |> Expect.equal (Just False)
            , test "a Badge with a malformed variant expression fails the decode (fail-closed)" <|
                \_ ->
                    JsonRender.decodeString badgeWithMalformedVariant
                        |> isErr
                        |> Expect.equal True
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
            , test "a directive object with an extra sibling in params fails the decode" <|
                \_ ->
                    JsonRender.decodeString paramsWithDirectiveSibling
                        |> isErr
                        |> Expect.equal True
            , test "an unknown per-component prop key fails the decode (strict props)" <|
                \_ ->
                    JsonRender.decodeString buttonWithUnknownProp
                        |> isErr
                        |> Expect.equal True
            , test "an unsupported ActionBinding field (onSuccess) fails the decode" <|
                \_ ->
                    JsonRender.decodeString bindingWithOnSuccess
                        |> isErr
                        |> Expect.equal True
            , test "a multi-binding event array fails the decode (no silent truncation)" <|
                \_ ->
                    JsonRender.decodeString multiBindingEvent
                        |> isErr
                        |> Expect.equal True
            , test "a single-element binding array still decodes" <|
                \_ ->
                    JsonRender.decodeString singleBindingArray
                        |> isErr
                        |> Expect.equal False
            , test "non-object props on an all-optional component (Card) fails the decode" <|
                \_ ->
                    JsonRender.decodeString cardWithNonObjectProps
                        |> isErr
                        |> Expect.equal True
            , test "array props on a Checkbox fails (does not silently drop the binding)" <|
                \_ ->
                    JsonRender.decodeString checkboxWithArrayProps
                        |> isErr
                        |> Expect.equal True
            ]
        , describe "present-but-malformed OPTIONAL fields (no silent drop)"
            -- An optional field that is present but malformed must fail the decode, not
            -- decode to `Nothing`. Dropping it silently degrades the manifest's declared
            -- semantics (a confirm dialog that never appears, a repeat that renders once).
            [ test "a confirm block missing its required `message` fails the decode" <|
                \_ ->
                    JsonRender.decodeString confirmMissingMessage
                        |> isErr
                        |> Expect.equal True
            , test "a non-object `confirm` (true) fails the decode, not a no-dialog button" <|
                \_ ->
                    JsonRender.decodeString confirmLiteralTrue
                        |> isErr
                        |> Expect.equal True
            , test "a confirm `message` carrying $computed fails the decode" <|
                \_ ->
                    JsonRender.decodeString confirmComputedMessage
                        |> isErr
                        |> Expect.equal True
            , test "a non-string confirm `confirmLabel` fails the decode" <|
                \_ ->
                    JsonRender.decodeString confirmNonStringLabel
                        |> isErr
                        |> Expect.equal True
            , test "a non-string confirm `cancelLabel` fails the decode" <|
                \_ ->
                    JsonRender.decodeString confirmNonStringCancelLabel
                        |> isErr
                        |> Expect.equal True
            , test "an explicit-null `confirm` fails the decode (optional, not nullable)" <|
                -- Pins the null semantics of the `optionalField` conversions: the pinned
                -- format models these fields as optional — absent or well-formed — so a
                -- present JSON null is malformed input, not a fancy way to omit.
                \_ ->
                    JsonRender.decodeString confirmExplicitNull
                        |> isErr
                        |> Expect.equal True
            , test "an explicit-null Card `title` still decodes (Expr-valued: null is a literal)" <|
                -- The counterpart boundary: Expr-valued optionals (Card/Alert title,
                -- Checkbox label/checked) accept null as `ELiteral null`, exactly as
                -- before the conversions.
                \_ ->
                    JsonRender.decodeString cardExplicitNullTitle
                        |> isErr
                        |> Expect.equal False
            , test "a malformed `repeat` fails the decode, not a once-rendered element" <|
                \_ ->
                    JsonRender.decodeString repeatMalformedStatePath
                        |> isErr
                        |> Expect.equal True
            , test "a non-object `repeat` (true) fails the decode" <|
                \_ ->
                    JsonRender.decodeString repeatLiteralTrue
                        |> isErr
                        |> Expect.equal True
            , test "a non-string repeat `key` fails the decode" <|
                \_ ->
                    JsonRender.decodeString repeatNonStringKey
                        |> isErr
                        |> Expect.equal True
            , test "a malformed Checkbox `checked` binding fails the decode" <|
                \_ ->
                    JsonRender.decodeString checkboxMalformedChecked
                        |> isErr
                        |> Expect.equal True
            , test "a malformed Checkbox `label` fails the decode" <|
                \_ ->
                    JsonRender.decodeString checkboxMalformedLabel
                        |> isErr
                        |> Expect.equal True
            , test "a malformed Alert `title` fails the decode" <|
                \_ ->
                    JsonRender.decodeString alertMalformedTitle
                        |> isErr
                        |> Expect.equal True
            , test "a malformed Card `title` fails the decode" <|
                \_ ->
                    JsonRender.decodeString cardMalformedTitle
                        |> isErr
                        |> Expect.equal True
            ]
        , describe "the FindingsTable wire-name alias (pre-2.0.0 compatibility)"
            [ test "a `FindingsTable` element decodes as a GroupedTable" <|
                \_ ->
                    JsonRender.decodeString findingsTableAlias
                        |> Result.toMaybe
                        |> Maybe.andThen (\spec -> Dict.get "t" spec.elements)
                        |> Maybe.map .componentType
                        |> Expect.equal (Just GroupedTable)
            ]
        ]


confirmMissingMessage : String
confirmMissingMessage =
    """
    { "root": "r"
    , "elements":
        { "r":
            { "type": "Button", "props": { "label": "x" }, "children": []
            , "on": { "press": { "action": "go", "confirm": { "title": "Sure?" } } }
            }
        }
    }
    """


confirmLiteralTrue : String
confirmLiteralTrue =
    """
    { "root": "r"
    , "elements":
        { "r":
            { "type": "Button", "props": { "label": "x" }, "children": []
            , "on": { "press": { "action": "go", "confirm": true } }
            }
        }
    }
    """


confirmComputedMessage : String
confirmComputedMessage =
    """
    { "root": "r"
    , "elements":
        { "r":
            { "type": "Button", "props": { "label": "x" }, "children": []
            , "on": { "press": { "action": "go", "confirm":
                { "title": "Sure?", "message": { "$computed": "evil" } } } }
            }
        }
    }
    """


confirmNonStringLabel : String
confirmNonStringLabel =
    """
    { "root": "r"
    , "elements":
        { "r":
            { "type": "Button", "props": { "label": "x" }, "children": []
            , "on": { "press": { "action": "go", "confirm":
                { "title": "Sure?", "message": "Go?", "confirmLabel": 5 } } }
            }
        }
    }
    """


confirmNonStringCancelLabel : String
confirmNonStringCancelLabel =
    """
    { "root": "r"
    , "elements":
        { "r":
            { "type": "Button", "props": { "label": "x" }, "children": []
            , "on": { "press": { "action": "go", "confirm":
                { "title": "Sure?", "message": "Go?", "cancelLabel": 5 } } }
            }
        }
    }
    """


confirmExplicitNull : String
confirmExplicitNull =
    """
    { "root": "r"
    , "elements":
        { "r":
            { "type": "Button", "props": { "label": "x" }, "children": []
            , "on": { "press": { "action": "go", "confirm": null } }
            }
        }
    }
    """


cardExplicitNullTitle : String
cardExplicitNullTitle =
    """
    { "root": "r"
    , "elements":
        { "r": { "type": "Card", "props": { "title": null }, "children": [] } }
    }
    """


repeatMalformedStatePath : String
repeatMalformedStatePath =
    """
    { "root": "r"
    , "elements":
        { "r": { "type": "Stack", "props": {}, "repeat": { "statePath": 5 }, "children": ["t"] }
        , "t": { "type": "Text", "props": { "value": "x" }, "children": [] }
        }
    }
    """


repeatLiteralTrue : String
repeatLiteralTrue =
    """
    { "root": "r"
    , "elements":
        { "r": { "type": "Stack", "props": {}, "repeat": true, "children": ["t"] }
        , "t": { "type": "Text", "props": { "value": "x" }, "children": [] }
        }
    }
    """


repeatNonStringKey : String
repeatNonStringKey =
    """
    { "root": "r"
    , "elements":
        { "r": { "type": "Stack", "props": {}, "repeat": { "statePath": "/xs", "key": 7 }, "children": ["t"] }
        , "t": { "type": "Text", "props": { "value": "x" }, "children": [] }
        }
    }
    """


checkboxMalformedChecked : String
checkboxMalformedChecked =
    """
    { "root": "r"
    , "elements":
        { "r": { "type": "Checkbox", "props": { "label": "x", "checked": { "$computed": "evil" } }, "children": [] } }
    }
    """


checkboxMalformedLabel : String
checkboxMalformedLabel =
    """
    { "root": "r"
    , "elements":
        { "r": { "type": "Checkbox", "props": { "label": { "$computed": "evil" } }, "children": [] } }
    }
    """


alertMalformedTitle : String
alertMalformedTitle =
    """
    { "root": "r"
    , "elements":
        { "r": { "type": "Alert", "props": { "tone": "info", "title": { "$computed": "evil" }, "message": "m" }, "children": [] } }
    }
    """


cardMalformedTitle : String
cardMalformedTitle =
    """
    { "root": "r"
    , "elements": { "r": { "type": "Card", "props": { "title": { "$computed": "evil" } }, "children": [] } }
    }
    """


findingsTableAlias : String
findingsTableAlias =
    """
    { "root": "t"
    , "elements":
        { "t": { "type": "FindingsTable", "props": { "bind": { "$state": "/results" } }, "children": [] } }
    }
    """


badgeWithVariant : String
badgeWithVariant =
    """
    { "root": "r"
    , "elements": { "r": { "type": "Badge", "props": { "value": { "$item": "label" }, "variant": { "$item": "state" } }, "children": [] } }
    }
    """


badgeWithoutVariant : String
badgeWithoutVariant =
    """
    { "root": "r"
    , "elements": { "r": { "type": "Badge", "props": { "value": { "$item": "label" } }, "children": [] } }
    }
    """


badgeWithMalformedVariant : String
badgeWithMalformedVariant =
    """
    { "root": "r"
    , "elements": { "r": { "type": "Badge", "props": { "value": "x", "variant": { "$computed": "evil" } }, "children": [] } }
    }
    """


{-| `Just True` when the element is a Badge carrying a `variant`, `Just False` for a Badge
without one, `Nothing` for a non-Badge element.
-}
badgeVariantPresent : Spec.UIElement -> Maybe Bool
badgeVariantPresent element =
    case element.props of
        BadgeP badge ->
            Just (badge.variant /= Nothing)

        _ ->
            Nothing


cardWithNonObjectProps : String
cardWithNonObjectProps =
    """
    { "root": "r"
    , "elements": { "r": { "type": "Card", "props": true, "children": [] } }
    }
    """


checkboxWithArrayProps : String
checkboxWithArrayProps =
    """
    { "root": "r"
    , "elements": { "r": { "type": "Checkbox", "props": [], "children": [] } }
    }
    """


buttonWithUnknownProp : String
buttonWithUnknownProp =
    """
    { "root": "r"
    , "elements":
        { "r": { "type": "Button", "props": { "label": "x", "disabled": true }, "children": [] } }
    }
    """


bindingWithOnSuccess : String
bindingWithOnSuccess =
    """
    { "root": "r"
    , "elements":
        { "r":
            { "type": "Button", "props": { "label": "x" }, "children": []
            , "on": { "press": { "action": "go", "onSuccess": { "navigate": "/elsewhere" } } }
            }
        }
    }
    """


multiBindingEvent : String
multiBindingEvent =
    """
    { "root": "r"
    , "elements":
        { "r":
            { "type": "Button", "props": { "label": "x" }, "children": []
            , "on": { "press": [ { "action": "a" }, { "action": "b" } ] }
            }
        }
    }
    """


singleBindingArray : String
singleBindingArray =
    """
    { "root": "r"
    , "elements":
        { "r":
            { "type": "Button", "props": { "label": "x" }, "children": []
            , "on": { "press": [ { "action": "a" } ] }
            }
        }
    }
    """


paramsWithDirectiveSibling : String
paramsWithDirectiveSibling =
    """
    { "root": "r"
    , "elements":
        { "r":
            { "type": "Button", "props": { "label": "x" }, "children": []
            , "on": { "press": { "action": "go", "params": { "target": { "$item": "id", "kind": "instance" } } } }
            }
        }
    }
    """


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
