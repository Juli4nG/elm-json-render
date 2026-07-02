module ExprTest exposing (suite)

import Expect
import Json.Decode as Decode exposing (Value)
import Json.Encode as Encode
import JsonRender.Expr as Expr exposing (Expr(..))
import Test exposing (Test, describe, test)


{-| A small host-state fixture mirroring the renderer-facing projection in
`contract/host-renderer-interface.md`.
-}
stateJson : String
stateJson =
    """
    { "selectAll": false
    , "instances":
        [ { "id": "i-0a1b2c3d", "name": "web-frontend-01", "selected": false, "scanState": "idle" }
        , { "id": "i-1b2c3d4e", "name": "api-backend-02",  "selected": true,  "scanState": "running" }
        , { "id": "i-2c3d4e5f", "name": "postgres-primary","selected": false, "scanState": "done" }
        ]
    , "results": null
    }
    """


state : Value
state =
    decode stateJson


decode : String -> Value
decode raw =
    case Decode.decodeString Decode.value raw of
        Ok v ->
            v

        Err _ ->
            Encode.null


{-| Build a repeat scope for a given instance index.
-}
rowCtx : Int -> Expr.Context
rowCtx index =
    let
        item =
            Expr.getByPath ("/instances/" ++ String.fromInt index) state
                |> Maybe.withDefault Encode.null
    in
    Expr.childContext "/instances" index item (Expr.rootContext state)


encode : Value -> String
encode =
    Encode.encode 0


suite : Test
suite =
    describe "JsonRender.Expr"
        [ describe "getByPath (RFC 6901)"
            [ test "nested array + object path" <|
                \_ ->
                    Expr.getByPath "/instances/2/name" state
                        |> Maybe.map encode
                        |> Expect.equal (Just "\"postgres-primary\"")
            , test "empty pointer returns whole value" <|
                \_ ->
                    Expr.getByPath "" (Encode.string "x")
                        |> Maybe.map encode
                        |> Expect.equal (Just "\"x\"")
            , test "missing token yields Nothing" <|
                \_ ->
                    Expr.getByPath "/instances/99/name" state
                        |> Expect.equal Nothing
            , test "bare field token (no leading slash)" <|
                \_ ->
                    Expr.getByPath "name"
                        (decode "{\"name\":\"x\"}")
                        |> Maybe.map encode
                        |> Expect.equal (Just "\"x\"")
            , test "~1 unescapes to slash" <|
                \_ ->
                    Expr.getByPath "/a~1b"
                        (decode "{\"a/b\":7}")
                        |> Maybe.map encode
                        |> Expect.equal (Just "7")
            ]
        , describe "decoder"
            [ test "$state decodes to EState" <|
                \_ ->
                    Decode.decodeString Expr.decoder "{\"$state\":\"/results\"}"
                        |> Expect.equal (Ok (EState "/results"))
            , test "$item decodes to EItem" <|
                \_ ->
                    Decode.decodeString Expr.decoder "{\"$item\":\"name\"}"
                        |> Expect.equal (Ok (EItem "name"))
            , test "$index decodes to EIndex" <|
                \_ ->
                    Decode.decodeString Expr.decoder "{\"$index\":true}"
                        |> Expect.equal (Ok EIndex)
            , test "a bare scalar decodes to a literal" <|
                \_ ->
                    Decode.decodeString Expr.decoder "\"hello\""
                        |> Result.map (Expr.resolve (Expr.rootContext state))
                        |> Result.map encode
                        |> Expect.equal (Ok "\"hello\"")
            , test "unsupported $-directive fails the decode (fail-closed)" <|
                \_ ->
                    Decode.decodeString Expr.decoder "{\"$cond\":true,\"$then\":1,\"$else\":2}"
                        |> isErr
                        |> Expect.equal True
            , test "$index with a non-true value fails" <|
                \_ ->
                    Decode.decodeString Expr.decoder "{\"$index\":false}"
                        |> isErr
                        |> Expect.equal True
            , test "a directive with an extra non-$ sibling fails (no silent drop)" <|
                \_ ->
                    Decode.decodeString Expr.decoder "{\"$item\":\"id\",\"kind\":\"instance\"}"
                        |> isErr
                        |> Expect.equal True
            ]
        , describe "resolve"
            [ test "$state reads global state" <|
                \_ ->
                    Expr.resolve (Expr.rootContext state) (EState "/selectAll")
                        |> encode
                        |> Expect.equal "false"
            , test "$item reads the repeat item field VALUE" <|
                \_ ->
                    Expr.resolve (rowCtx 0) (EItem "name")
                        |> encode
                        |> Expect.equal "\"web-frontend-01\""
            , test "$index is the row index number" <|
                \_ ->
                    Expr.resolve (rowCtx 2) EIndex
                        |> encode
                        |> Expect.equal "2"
            , test "resolveDisplay stringifies a scalar" <|
                \_ ->
                    Expr.resolveDisplay (rowCtx 1) (EItem "scanState")
                        |> Expect.equal "running"
            , test "resolveBool reads a per-row checkbox binding" <|
                \_ ->
                    Expr.resolveBool (rowCtx 1) (EBindItem "selected")
                        |> Expect.equal True
            , test "$template interpolates a bare item field (item-first)" <|
                \_ ->
                    Expr.resolveDisplay (rowCtx 0)
                        (ETemplate "Queue a scan for ${name}?")
                        |> Expect.equal "Queue a scan for web-frontend-01?"
            , test "$template interpolates an absolute pointer" <|
                \_ ->
                    Expr.resolveDisplay (Expr.rootContext state)
                        (ETemplate "all=${/selectAll}")
                        |> Expect.equal "all=false"
            ]
        , describe "writeBackPath"
            [ test "$bindItem write-back path uses the repeat basePath" <|
                \_ ->
                    Expr.writeBackPath (rowCtx 2) (EBindItem "selected")
                        |> Expect.equal (Just "/instances/2/selected")
            , test "$bindState write-back path is its own pointer" <|
                \_ ->
                    Expr.writeBackPath (Expr.rootContext state) (EBindState "/selectAll")
                        |> Expect.equal (Just "/selectAll")
            , test "whole-item $bindItem write-back path has no trailing slash" <|
                \_ ->
                    Expr.writeBackPath (rowCtx 2) (EBindItem "")
                        |> Expect.equal (Just "/instances/2")
            , test "read-only expression has no write-back path" <|
                \_ ->
                    Expr.writeBackPath (rowCtx 0) (EItem "name")
                        |> Expect.equal Nothing
            ]
        , describe "resolveParams (pinned §5.1)"
            [ test "$item NESTED in an array resolves to the literal id VALUE" <|
                \_ ->
                    Expr.resolveParams (rowCtx 2)
                        (decode "{\"targetInstanceIds\":[{\"$item\":\"id\"}]}")
                        |> encode
                        |> Expect.equal "{\"targetInstanceIds\":[\"i-2c3d4e5f\"]}"
            , test "an empty array passes through verbatim (use-selection signal)" <|
                \_ ->
                    Expr.resolveParams (Expr.rootContext state)
                        (decode "{\"targetInstanceIds\":[]}")
                        |> encode
                        |> Expect.equal "{\"targetInstanceIds\":[]}"
            , test "$item at the TOP LEVEL resolves to the absolute state PATH" <|
                \_ ->
                    Expr.resolveParams (rowCtx 2)
                        (decode "{\"target\":{\"$item\":\"id\"}}")
                        |> encode
                        |> Expect.equal "{\"target\":\"/instances/2/id\"}"
            ]
        ]


isErr : Result e a -> Bool
isErr result =
    case result of
        Err _ ->
            True

        Ok _ ->
            False
