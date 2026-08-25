module BadgeToneTest exposing (suite)

{-| Coverage for `JsonRender.Render.badgeTone`, the value → tone-class mapping the host stylesheet
keys its badge colors on. Exposed so a host can tint chrome outside the rendered tree with the same
table the renderer uses, rather than reimplementing it and drifting.

Asserted on the function rather than through rendered markup: the tone lands in a class attribute,
and the interesting cases are the tokenizing ones, which read far more clearly as a list.

-}

import Expect
import JsonRender.Render as Render
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "JsonRender.Render.badgeTone"
        [ test "the in-flight states all tone as info, suffix or ellipsis or not" <|
            \_ ->
                -- `stopping` is in flight like queued/running, and the neutral tone it used to fall
                -- through to read as already-over, which is the one thing that state must not say.
                -- The ellipsis is punctuation on the display word, so the tone must not depend on
                -- the publisher's typography.
                Expect.equal [ "info", "info", "info", "info", "info" ]
                    ([ "queued", "running", "running · 0:15", "stopping", "stopping…" ]
                        |> List.map Render.badgeTone
                    )
        , test "the settled states keep their own tones, so the ellipsis rule changed nothing else" <|
            \_ ->
                Expect.equal [ "neutral", "success", "danger", "neutral" ]
                    ([ "idle", "done", "error", "cancelled" ] |> List.map Render.badgeTone)
        , test "leading whitespace and tabs still tokenize to the state word" <|
            \_ ->
                Expect.equal [ "success", "success" ]
                    ([ " done", "\tdone · 2s" ] |> List.map Render.badgeTone)
        , test "a word this table does not know is neutral, and a manifest variant owns its tone" <|
            \_ ->
                -- A publisher with its own vocabulary gets the neutral fall-through and supplies
                -- `variant` for a tone, which is why no publisher's private verb needs an arm here.
                Expect.equal [ "neutral", "neutral", "neutral" ]
                    ([ "scanning · 0:15", "snapshotting", "" ] |> List.map Render.badgeTone)
        ]
