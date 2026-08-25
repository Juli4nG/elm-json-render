module CountPillsTest exposing (suite)

{-| Coverage for the `CountPills` element: the pill summary, the publisher/host vocabulary
split, `emptyLabel`, and the two deprecated wire names.

Two rules carry the weight here.

The **vocabulary** rule: the renderer counts rows and orders groups, but every word comes from
the manifest when it names one and from the host's `CountPillDefaults` when it does not. That is
what lets a manifest published before these prop keys existed keep reading in its host's words.

The **empty-state** rule: with no groups to show, an absent `emptyLabel` keeps the renderer's
provisional "No <plural> yet"; a resolved label replaces it; a resolved EMPTY string renders no
empty-state node at all, because only the publisher knows whether an empty table means "nothing
bound yet" or "finished, and there was nothing".

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


specOf : String -> Spec
specOf raw =
    case JsonRender.decodeString raw of
        Ok spec ->
            spec

        Err _ ->
            { root = "missing", elements = Dict.empty, state = Encode.null }


{-| A host whose rows are findings grouped by severity, severest first. Stands in for any host
that hands the renderer its own vocabulary through `Render.Options`.
-}
severityOptions : Render.Options
severityOptions =
    { allowedIframeOrigins = []
    , hostName = "the host application"
    , countPills =
        { groupBy = "severity"
        , groupOrder = [ "critical", "high", "medium", "low", "info" ]
        , itemNoun = "finding"
        , itemNounPlural = "findings"
        }
    }


renderWith : Render.Options -> String -> Encode.Value -> Query.Single Render.Msg
renderWith options raw state =
    Render.view options (specOf raw) state Render.init
        |> Query.fromHtml


{-| The element with whatever extra props are spliced in, always bound to `/results`.
-}
tableWith : String -> String
tableWith extraProps =
    """
    { "root": "t"
    , "elements":
        { "t":
            { "type": "CountPills"
            , "props": { "bind": { "$state": "/results" }@@ }
            }
        }
    }
    """
        |> String.replace "@@" extraProps


{-| The same element under a deprecated wire name, with no vocabulary keys at all: exactly the
shape a manifest published before the rename still has on the wire.
-}
legacyTable : String -> String
legacyTable wireName =
    """
    { "root": "t"
    , "elements":
        { "t":
            { "type": "@@"
            , "props": { "bind": { "$state": "/results" }, "groupBy": "severity" }
            }
        }
    }
    """
        |> String.replace "@@" wireName


{-| A scrambled set of severities so pass-through, alphabetical and count order all differ from
the host's rank: 1 low, 1 medium, 2 high, 1 critical (no `info`).
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


{-| Two lows and one critical: enough that alphabetical order, descending-count order, and the
host's own order all disagree.
-}
mixedState : Encode.Value
mixedState =
    let
        row severity =
            Encode.object [ ( "severity", Encode.string severity ) ]
    in
    Encode.object [ ( "results", Encode.list row [ "low", "critical", "low" ] ) ]


oneHighState : Encode.Value
oneHighState =
    Encode.object
        [ ( "results"
          , Encode.list identity [ Encode.object [ ( "severity", Encode.string "high" ) ] ]
          )
        ]


noRowsState : Encode.Value
noRowsState =
    Encode.object [ ( "results", Encode.list identity [] ) ]


nullState : Encode.Value
nullState =
    Encode.object [ ( "results", Encode.null ) ]


{-| Every optional `CountPills` prop, present but malformed. Each must reject the whole manifest
rather than decoding as absent, which is what an Elm decoder does by default and what 2.x did at
this element.

The distinction matters most for `groupBy` and `emptyLabel`: treated as absent, a malformed one
silently falls back to the host's vocabulary, so a publisher's typo ships as a table that counts
the wrong field or reassures with the wrong sentence, with nothing anywhere saying so.

-}
malformedProps : List ( String, String )
malformedProps =
    [ ( "a null groupBy is rejected, not read as absent"
      , """, "groupBy": null """
      )
    , ( "a non-string groupBy is rejected"
      , """, "groupBy": 7 """
      )
    , ( "a null groupOrder is rejected"
      , """, "groupOrder": null """
      )
    , ( "a groupOrder that is not a list is rejected"
      , """, "groupOrder": "critical" """
      )
    , ( "a groupOrder carrying a non-string MEMBER is rejected"
      , """, "groupOrder": [ "critical", 3 ] """
      )
    , ( "a groupOrder carrying a null member is rejected"
      , """, "groupOrder": [ "critical", null ] """
      )
    , ( "a null itemNoun is rejected"
      , """, "itemNoun": null """
      )
    , ( "a non-string itemNoun is rejected"
      , """, "itemNoun": true """
      )
    , ( "a null itemNounPlural is rejected"
      , """, "itemNounPlural": null """
      )
    , ( "a non-string itemNounPlural is rejected"
      , """, "itemNounPlural": [ "findings" ] """
      )
    , ( "an emptyLabel carrying an unsupported directive is rejected"
      , """, "emptyLabel": { "$computed": "summarize" } """
      )
    , ( "an emptyLabel carrying a malformed directive is rejected"
      , """, "emptyLabel": { "$item": 3 } """
      )
    , ( "an emptyLabel directive with extra siblings is rejected"
      , """, "emptyLabel": { "$state": "/x", "junk": true } """
      )
    ]


{-| The well-formed counterpart of each shape above, so a decoder that rejected everything
outright could not pass the table.
-}
wellFormedProps : List String
wellFormedProps =
    [ """, "groupBy": "severity" """
    , """, "groupOrder": [ "critical", "high" ] """
    , """, "groupOrder": [] """
    , """, "itemNoun": "finding" """
    , """, "itemNounPlural": "findings" """
    , """, "emptyLabel": "No vulnerabilities found" """
    , """, "emptyLabel": { "$state": "/message" } """
    ]


resultOk : Result e a -> Bool
resultOk result =
    case result of
        Ok _ ->
            True

        Err _ ->
            False


conditionalEmptyLabel : String
conditionalEmptyLabel =
    """, "emptyLabel": { "$cond": { "$state": "/results" }, "$then": "No vulnerabilities found", "$else": "" } """


suite : Test
suite =
    describe "JsonRender.Render CountPills"
        [ describe "the pill summary"
            [ test "renders one pill per present group (zero-count groups absent)" <|
                \_ ->
                    renderWith severityOptions (tableWith "") scrambledState
                        |> Query.findAll [ Selector.class "jr-counts__pill" ]
                        |> Query.count (Expect.equal 4)
            , test "orders pills by the host's groupOrder, not alphabetically" <|
                \_ ->
                    let
                        pills =
                            renderWith severityOptions (tableWith "") scrambledState
                                |> Query.findAll [ Selector.class "jr-counts__pill" ]
                    in
                    Expect.all
                        [ \ps -> ps |> Query.index 0 |> Query.has [ Selector.class "jr-counts__pill--critical" ]
                        , \ps -> ps |> Query.index 1 |> Query.has [ Selector.class "jr-counts__pill--high" ]
                        , \ps -> ps |> Query.index 2 |> Query.has [ Selector.class "jr-counts__pill--medium" ]
                        , \ps -> ps |> Query.index 3 |> Query.has [ Selector.class "jr-counts__pill--low" ]
                        ]
                        pills
            , test "each pill carries a dot, count, and label" <|
                \_ ->
                    renderWith severityOptions (tableWith "") scrambledState
                        |> Query.find [ Selector.class "jr-counts__pill--high" ]
                        |> Expect.all
                            [ Query.has [ Selector.class "jr-counts__dot" ]
                            , Query.has [ Selector.class "jr-counts__count", Selector.text "2" ]
                            , Query.has [ Selector.class "jr-counts__label", Selector.text "high" ]
                            ]
            , test "renders a leading total of all counts, in the host's plural noun" <|
                \_ ->
                    renderWith severityOptions (tableWith "") scrambledState
                        |> Query.find [ Selector.class "jr-counts__total" ]
                        |> Query.has [ Selector.text "5 findings" ]
            , test "a single row uses the singular noun" <|
                \_ ->
                    renderWith severityOptions (tableWith "") oneHighState
                        |> Query.find [ Selector.class "jr-counts__total" ]
                        |> Query.has [ Selector.text "1 finding" ]
            ]
        , describe "vocabulary"
            [ test "the manifest's own nouns win over the host's" <|
                \_ ->
                    renderWith severityOptions
                        (tableWith """, "itemNoun": "alert", "itemNounPlural": "alerts" """)
                        oneHighState
                        |> Query.find [ Selector.class "jr-counts__total" ]
                        |> Query.has [ Selector.text "1 alert" ]
            , test "the manifest's own groupOrder wins over the host's" <|
                \_ ->
                    renderWith severityOptions
                        (tableWith """, "groupOrder": [ "low", "critical" ] """)
                        mixedState
                        |> Query.findAll [ Selector.class "jr-counts__pill" ]
                        |> Query.index 0
                        |> Query.has [ Selector.class "jr-counts__pill--low" ]
            , test "the manifest's own groupBy wins over the host's" <|
                \_ ->
                    renderWith severityOptions
                        (tableWith """, "groupBy": "kind" """)
                        (Encode.object
                            [ ( "results"
                              , Encode.list identity
                                    [ Encode.object
                                        [ ( "severity", Encode.string "high" )
                                        , ( "kind", Encode.string "package" )
                                        ]
                                    ]
                              )
                            ]
                        )
                        |> Query.has [ Selector.class "jr-counts__pill--package" ]
            , test "with no groupOrder anywhere, the biggest group leads" <|
                \_ ->
                    renderWith Render.defaultOptions
                        (tableWith """, "groupBy": "severity" """)
                        mixedState
                        |> Query.findAll [ Selector.class "jr-counts__pill" ]
                        |> Query.index 0
                        |> Query.has [ Selector.class "jr-counts__pill--low" ]
            , test "groupOrder ranks case-insensitively" <|
                \_ ->
                    renderWith Render.defaultOptions
                        (tableWith """, "groupBy": "severity", "groupOrder": [ "CRITICAL", "LOW" ] """)
                        mixedState
                        |> Query.findAll [ Selector.class "jr-counts__pill" ]
                        |> Query.index 0
                        |> Query.has [ Selector.class "jr-counts__pill--critical" ]
            , test "the renderer's own fallbacks are plain items grouped by `group`" <|
                \_ ->
                    renderWith Render.defaultOptions
                        (tableWith "")
                        (Encode.object
                            [ ( "results"
                              , Encode.list identity
                                    [ Encode.object [ ( "group", Encode.string "a" ) ]
                                    , Encode.object [ ( "group", Encode.string "a" ) ]
                                    ]
                              )
                            ]
                        )
                        |> Query.find [ Selector.class "jr-counts__total" ]
                        |> Query.has [ Selector.text "2 items" ]
            , test "a row missing the grouping field counts as `ungrouped`" <|
                \_ ->
                    renderWith severityOptions
                        (tableWith "")
                        (Encode.object
                            [ ( "results", Encode.list identity [ Encode.object [] ] ) ]
                        )
                        |> Query.has [ Selector.class "jr-counts__pill--ungrouped" ]
            ]
        , describe "emptyLabel"
            [ test "an absent emptyLabel keeps the renderer's provisional default" <|
                \_ ->
                    renderWith severityOptions (tableWith "") nullState
                        |> Query.has
                            [ Selector.class "jr-counts--empty"
                            , Selector.text "No findings yet"
                            ]
            , test "a supplied emptyLabel is what an empty table says instead" <|
                \_ ->
                    renderWith severityOptions
                        (tableWith """, "emptyLabel": "No vulnerabilities found" """)
                        noRowsState
                        |> Query.has [ Selector.text "No vulnerabilities found" ]
            , test "an emptyLabel resolving to the empty string renders no empty-state node at all" <|
                \_ ->
                    renderWith severityOptions (tableWith """, "emptyLabel": "" """) noRowsState
                        |> Query.findAll [ Selector.class "jr-counts" ]
                        |> Query.count (Expect.equal 0)
            , test "a supplied label does render a node (guards the count above)" <|
                \_ ->
                    renderWith severityOptions
                        (tableWith """, "emptyLabel": "No vulnerabilities found" """)
                        noRowsState
                        |> Query.findAll [ Selector.class "jr-counts--empty" ]
                        |> Query.count (Expect.equal 1)
            , test "an expression-valued emptyLabel resolves against state" <|
                \_ ->
                    renderWith severityOptions (tableWith conditionalEmptyLabel) noRowsState
                        |> Query.has [ Selector.text "No vulnerabilities found" ]
            , test "the same expression stays silent when nothing is bound (null results)" <|
                \_ ->
                    renderWith severityOptions (tableWith conditionalEmptyLabel) nullState
                        |> Query.findAll [ Selector.class "jr-counts" ]
                        |> Query.count (Expect.equal 0)
            , test "a table WITH rows is unaffected by emptyLabel" <|
                \_ ->
                    renderWith severityOptions
                        (tableWith """, "emptyLabel": "No vulnerabilities found" """)
                        oneHighState
                        |> Query.has [ Selector.text "1 finding", Selector.text "high" ]
            ]
        , describe "optional does not mean lenient"
            (malformedProps
                |> List.map
                    (\( label, prop ) ->
                        test label <|
                            \_ ->
                                JsonRender.decodeString (tableWith prop)
                                    |> Result.map (always "accepted")
                                    |> Expect.err
                    )
            )
        , test "the well-formed shapes those cases vary from all still decode (guards the table)" <|
            \_ ->
                wellFormedProps
                    |> List.map (tableWith >> JsonRender.decodeString >> resultOk)
                    |> Expect.equal (List.map (always True) wellFormedProps)
        , describe "deprecated wire names"
            [ test "`GroupedTable` (the 2.x name) still decodes to CountPills" <|
                \_ ->
                    renderWith severityOptions (legacyTable "GroupedTable") scrambledState
                        |> Query.findAll [ Selector.class "jr-counts__pill" ]
                        |> Query.count (Expect.equal 4)
            , test "`FindingsTable` (the pre-2.0.0 name) still decodes to CountPills" <|
                \_ ->
                    renderWith severityOptions (legacyTable "FindingsTable") scrambledState
                        |> Query.findAll [ Selector.class "jr-counts__pill" ]
                        |> Query.count (Expect.equal 4)
            , test "an unchanged legacy manifest counts in the host's nouns" <|
                \_ ->
                    renderWith severityOptions (legacyTable "GroupedTable") oneHighState
                        |> Query.find [ Selector.class "jr-counts__total" ]
                        |> Query.has [ Selector.text "1 finding" ]
            , test "an unchanged legacy manifest reads its empty state in the host's words" <|
                \_ ->
                    renderWith severityOptions (legacyTable "FindingsTable") noRowsState
                        |> Query.has [ Selector.text "No findings yet" ]
            , test "the host's groupOrder puts critical ahead of the larger low group" <|
                \_ ->
                    renderWith severityOptions (legacyTable "GroupedTable") mixedState
                        |> Query.findAll [ Selector.class "jr-counts__pill" ]
                        |> Query.index 0
                        |> Query.has [ Selector.class "jr-counts__pill--critical" ]
            ]
        ]
