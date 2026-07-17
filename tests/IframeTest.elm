module IframeTest exposing (suite)

{-| Focused coverage for the origin-pinned `Iframe` element. The origin-pin is the whole
safety boundary: an `<iframe>` is emitted only for an https `src` whose origin is an exact
member of the host-provided allowlist; everything else self-hides to a placeholder.
-}

import Dict
import Expect
import Html.Attributes as Attr
import Json.Encode as Encode
import JsonRender
import JsonRender.Render as Render
import JsonRender.Spec exposing (Spec)
import Test exposing (Test, describe, test)
import Test.Html.Query as Query
import Test.Html.Selector as Selector


allowedOrigins : List String
allowedOrigins =
    [ "https://1-2-3-4.sslip.io" ]


{-| A minimal single-Iframe manifest binding `src` to `/embedUrl`.
-}
iframeManifest : String
iframeManifest =
    """
    { "root": "frame"
    , "elements":
        { "frame":
            { "type": "Iframe"
            , "props": { "src": { "$state": "/embedUrl" }, "title": "CloudShield live UI" }
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


stateWith : String -> Encode.Value
stateWith embedUrl =
    Encode.object [ ( "embedUrl", Encode.string embedUrl ) ]


render : String -> Query.Single Render.Msg
render embedUrl =
    Render.view allowedOrigins (specOf iframeManifest) (stateWith embedUrl) Render.init
        |> Query.fromHtml


suite : Test
suite =
    describe "JsonRender.Render Iframe (origin-pinned, fail-closed)"
        [ test "an https src whose origin is allowlisted renders an <iframe> with that src" <|
            \_ ->
                render "https://1-2-3-4.sslip.io/app"
                    |> Query.find [ Selector.tag "iframe" ]
                    |> Query.has [ Selector.attribute (Attr.src "https://1-2-3-4.sslip.io/app") ]
        , test "an https src whose origin is NOT allowlisted renders no iframe" <|
            \_ ->
                render "https://evil.example.com/app"
                    |> Query.findAll [ Selector.tag "iframe" ]
                    |> Query.count (Expect.equal 0)
        , test "a non-https (http) src with a matching host renders no iframe" <|
            \_ ->
                render "http://1-2-3-4.sslip.io/app"
                    |> Query.findAll [ Selector.tag "iframe" ]
                    |> Query.count (Expect.equal 0)
        , test "an empty (unresolved) src renders no iframe" <|
            \_ ->
                render ""
                    |> Query.findAll [ Selector.tag "iframe" ]
                    |> Query.count (Expect.equal 0)
        , test "an Iframe with required src + title decodes successfully" <|
            \_ ->
                JsonRender.decodeString iframeManifest
                    |> isOk
                    |> Expect.equal True
        , test "an Iframe with a stray prop key fails the decode (fail-closed)" <|
            \_ ->
                JsonRender.decodeString iframeStrayProp
                    |> isOk
                    |> Expect.equal False
        ]


iframeStrayProp : String
iframeStrayProp =
    """
    { "root": "frame"
    , "elements":
        { "frame":
            { "type": "Iframe"
            , "props":
                { "src": "https://1-2-3-4.sslip.io"
                , "title": "x"
                , "referrerpolicy": "unsafe-url"
                }
            }
        }
    }
    """


isOk : Result e a -> Bool
isOk result =
    case result of
        Ok _ ->
            True

        Err _ ->
            False
