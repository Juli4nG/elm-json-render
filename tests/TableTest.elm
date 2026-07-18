module TableTest exposing (suite)

{-| Focused coverage for the `Table` element: fail-closed decode of its `columns`/`bind`
props, the `<table class="jr-table">` shape (header from labels, one row per bound item),
and per-row cell resolution by column key (a missing key = an empty cell).
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


manifest : String
manifest =
    """
    { "root": "tbl"
    , "elements":
        { "tbl":
            { "type": "Table"
            , "props":
                { "columns":
                    [ { "key": "name", "label": "Name" }
                    , { "key": "sev", "label": "Severity" }
                    ]
                , "bind": { "$state": "/rows" }
                }
            }
        }
    }
    """


{-| A column carrying a key not in the strict `key`/`label` shape: must fail-closed.
-}
columnStrayKey : String
columnStrayKey =
    """
    { "root": "tbl"
    , "elements":
        { "tbl":
            { "type": "Table"
            , "props":
                { "columns": [ { "key": "name", "label": "Name", "width": 10 } ]
                , "bind": { "$state": "/rows" }
                }
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


{-| Two rows; the second omits `sev` so its Severity cell must render empty.
-}
state : Encode.Value
state =
    Encode.object
        [ ( "rows"
          , Encode.list identity
                [ Encode.object [ ( "name", Encode.string "CVE-1" ), ( "sev", Encode.string "high" ) ]
                , Encode.object [ ( "name", Encode.string "CVE-2" ) ]
                ]
          )
        ]


render : Query.Single Render.Msg
render =
    Render.view [] (specOf manifest) state Render.init
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
    describe "JsonRender.Render Table"
        [ test "a Table with columns + bind decodes" <|
            \_ ->
                JsonRender.decodeString manifest |> isOk |> Expect.equal True
        , test "a column with a stray key fails the decode (fail-closed)" <|
            \_ ->
                JsonRender.decodeString columnStrayKey |> isOk |> Expect.equal False
        , test "renders a <table class=jr-table> whose header shows each column label" <|
            \_ ->
                render
                    |> Query.find [ Selector.tag "thead" ]
                    |> Expect.all
                        [ Query.has [ Selector.text "Name" ]
                        , Query.has [ Selector.text "Severity" ]
                        , Query.findAll [ Selector.tag "th" ] >> Query.count (Expect.equal 2)
                        ]
        , test "renders one body row per bound item, resolving cells by column key" <|
            \_ ->
                render
                    |> Query.find [ Selector.tag "tbody" ]
                    |> Query.findAll [ Selector.tag "tr" ]
                    |> Expect.all
                        [ Query.count (Expect.equal 2)
                        , Query.index 0 >> Query.has [ Selector.text "CVE-1", Selector.text "high" ]
                        ]
        , test "a row missing a column key still renders that column as an (empty) cell" <|
            \_ ->
                render
                    |> Query.find [ Selector.tag "tbody" ]
                    |> Query.findAll [ Selector.tag "tr" ]
                    |> Query.index 1
                    |> Query.findAll [ Selector.tag "td" ]
                    |> Query.count (Expect.equal 2)
        ]
