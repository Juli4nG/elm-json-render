module AlertTest exposing (suite)

{-| Focused coverage for the `Alert` element: fail-closed decode of its `tone` (an unknown
tone is rejected), and the `div.jr-alert.jr-alert--<tone>` render shape with an optional
title span and an expression-resolved message.
-}

import Dict
import Expect
import Json.Encode as Encode
import JsonRender
import JsonRender.Render as Render
import JsonRender.Spec exposing (Spec)
import Test exposing (Test, describe, test)
import Test.Html.Query as Query
import Test.Html.Selector as Selector


{-| A warning Alert whose message is a `$template` reading state.
-}
manifest : String
manifest =
    """
    { "root": "a"
    , "elements":
        { "a":
            { "type": "Alert"
            , "props":
                { "tone": "warning"
                , "title": "Heads up"
                , "message": { "$template": "Found ${/count} issues" }
                }
            }
        }
    }
    """


unknownTone : String
unknownTone =
    """
    { "root": "a"
    , "elements":
        { "a":
            { "type": "Alert"
            , "props": { "tone": "fatal", "message": "boom" }
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
    Render.view [] (specOf raw) (Encode.object [ ( "count", Encode.int 3 ) ]) Render.init
        |> Query.fromHtml


isOk : Result e a -> Bool
isOk result =
    case result of
        Ok _ ->
            True

        Err _ ->
            False


suite : Test
suite =
    describe "JsonRender.Render Alert"
        [ test "a known tone decodes" <|
            \_ ->
                JsonRender.decodeString manifest |> isOk |> Expect.equal True
        , test "an unknown tone fails the decode (fail-closed)" <|
            \_ ->
                JsonRender.decodeString unknownTone |> isOk |> Expect.equal False
        , test "renders div.jr-alert with the tone modifier, title span, and resolved message" <|
            \_ ->
                render manifest
                    |> Query.find [ Selector.class "jr-alert" ]
                    |> Expect.all
                        [ Query.has [ Selector.class "jr-alert--warning" ]
                        , Query.has [ Selector.class "jr-alert__title", Selector.text "Heads up" ]
                        , Query.has [ Selector.class "jr-alert__message", Selector.text "Found 3 issues" ]
                        ]
        , test "omitting title renders no title span" <|
            \_ ->
                render noTitleManifest
                    |> Query.findAll [ Selector.class "jr-alert__title" ]
                    |> Query.count (Expect.equal 0)
        ]


{-| A valid Alert with no title, to assert the title span is absent when unset.
-}
noTitleManifest : String
noTitleManifest =
    """
    { "root": "a"
    , "elements":
        { "a":
            { "type": "Alert"
            , "props": { "tone": "info", "message": "no title here" }
            }
        }
    }
    """
