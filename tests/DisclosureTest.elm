module DisclosureTest exposing (suite)

{-| Focused coverage for the `Disclosure` element: fail-closed decode of its props (an
unknown prop key is rejected; `open` defaults to `False`), and the native `<details>` render
shape with a `jr-disclosure__summary` carrying the resolved `label` and the children inside a
`jr-disclosure__body`, with the `open` attribute present only when `open == True`.
-}

import Dict
import Expect
import Html.Attributes as Attr
import Json.Encode as Encode
import JsonRender
import JsonRender.Render as Render
import JsonRender.Spec as Spec exposing (Props(..), Spec)
import Test exposing (Test, describe, test)
import Test.Html.Query as Query
import Test.Html.Selector as Selector


labelOnly : String
labelOnly =
    """
    { "root": "d"
    , "elements":
        { "d":
            { "type": "Disclosure"
            , "props": { "label": "Scan history" }
            , "children": ["kid"]
            }
        , "kid":
            { "type": "Text", "props": { "value": "inside body" } }
        }
    }
    """


openTrue : String
openTrue =
    """
    { "root": "d"
    , "elements":
        { "d":
            { "type": "Disclosure"
            , "props": { "label": "Scan history", "open": true }
            , "children": ["kid"]
            }
        , "kid":
            { "type": "Text", "props": { "value": "inside body" } }
        }
    }
    """


unknownProp : String
unknownProp =
    """
    { "root": "d"
    , "elements":
        { "d":
            { "type": "Disclosure"
            , "props": { "label": "x", "expanded": true }
            , "children": []
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


render : String -> Query.Single Render.Msg
render raw =
    Render.view [] (specOf raw) Encode.null Render.init
        |> Query.fromHtml


isOk : Result e a -> Bool
isOk result =
    case result of
        Ok _ ->
            True

        Err _ ->
            False


{-| The decoded `open` flag of the root disclosure, or `Nothing` if it isn't one.
-}
openFlag : String -> Maybe Bool
openFlag raw =
    Dict.get "d" (specOf raw).elements
        |> Maybe.andThen
            (\el ->
                case el.props of
                    DisclosureP props ->
                        Just props.open

                    _ ->
                        Nothing
            )


suite : Test
suite =
    describe "JsonRender.Render Disclosure"
        [ test "decodes with a label only, open defaulting to False" <|
            \_ ->
                Expect.equal (Just False) (openFlag labelOnly)
        , test "decodes with open:true" <|
            \_ ->
                Expect.equal (Just True) (openFlag openTrue)
        , test "an unknown prop key fails the decode (fail-closed)" <|
            \_ ->
                JsonRender.decodeString unknownProp |> isOk |> Expect.equal False
        , test "renders details.jr-disclosure with a summary label and the children in the body" <|
            \_ ->
                render labelOnly
                    |> Query.find [ Selector.class "jr-disclosure" ]
                    |> Expect.all
                        [ Query.has [ Selector.class "jr-disclosure__summary", Selector.text "Scan history" ]
                        , Query.has [ Selector.class "jr-disclosure__body", Selector.text "inside body" ]
                        ]
        , test "the open attribute is present when open:true" <|
            \_ ->
                render openTrue
                    |> Query.find [ Selector.class "jr-disclosure" ]
                    |> Query.has [ Selector.attribute (Attr.attribute "open" "") ]
        , test "the open attribute is absent by default" <|
            \_ ->
                render labelOnly
                    |> Query.find [ Selector.class "jr-disclosure" ]
                    |> Query.hasNot [ Selector.attribute (Attr.attribute "open" "") ]
        ]
