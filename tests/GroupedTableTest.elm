module GroupedTableTest exposing (suite)

{-| Coverage for the `GroupedTable` element's summary rendering: severity-ordered pills
(critical, high, medium, low, info — not alphabetical), zero-count groups dropped, a leading
total, and the muted empty state.
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
    { "root": "t"
    , "elements":
        { "t":
            { "type": "GroupedTable"
            , "props": { "bind": { "$state": "/results" }, "groupBy": "severity" }
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


{-| A scrambled set of severities so a pass-through/alphabetical order would differ from the
severity rank: 1 low, 1 medium, 2 high, 1 critical (no `info`).
-}
scrambledState : Encode.Value
scrambledState =
    let
        row severity =
            Encode.object [ ( "severity", Encode.string severity ) ]
    in
    Encode.object
        [ ( "results"
          , Encode.list row [ "low", "high", "medium", "critical", "high" ]
          )
        ]


render : Encode.Value -> Query.Single Render.Msg
render state =
    Render.view [] (specOf manifest) state Render.init
        |> Query.fromHtml


suite : Test
suite =
    describe "JsonRender.Render GroupedTable (severity-ordered pill summary)"
        [ test "renders one pill per present group (zero-count groups absent)" <|
            \_ ->
                render scrambledState
                    |> Query.findAll [ Selector.class "jr-grouped-table__group" ]
                    |> Query.count (Expect.equal 4)
        , test "orders pills by severity rank, not alphabetically (critical first, then high)" <|
            \_ ->
                let
                    groups =
                        render scrambledState
                            |> Query.findAll [ Selector.class "jr-grouped-table__group" ]
                in
                Expect.all
                    [ \gs -> gs |> Query.index 0 |> Query.has [ Selector.class "jr-grouped-table__group--critical" ]
                    , \gs -> gs |> Query.index 1 |> Query.has [ Selector.class "jr-grouped-table__group--high" ]
                    , \gs -> gs |> Query.index 2 |> Query.has [ Selector.class "jr-grouped-table__group--medium" ]
                    , \gs -> gs |> Query.index 3 |> Query.has [ Selector.class "jr-grouped-table__group--low" ]
                    ]
                    groups
        , test "each pill carries a dot, count, and label" <|
            \_ ->
                render scrambledState
                    |> Query.find
                        [ Selector.class "jr-grouped-table__group--high" ]
                    |> Expect.all
                        [ Query.has [ Selector.class "jr-grouped-table__dot" ]
                        , Query.has [ Selector.class "jr-grouped-table__count", Selector.text "2" ]
                        , Query.has [ Selector.class "jr-grouped-table__label", Selector.text "high" ]
                        ]
        , test "renders a leading total of all counts" <|
            \_ ->
                render scrambledState
                    |> Query.find [ Selector.class "jr-grouped-table__total" ]
                    |> Query.has [ Selector.text "5 total" ]
        , test "a null bind renders the muted empty state" <|
            \_ ->
                render (Encode.object [ ( "results", Encode.null ) ])
                    |> Query.has
                        [ Selector.class "jr-grouped-table--empty"
                        , Selector.text "No rows yet"
                        ]
        ]
