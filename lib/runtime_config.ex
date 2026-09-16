defmodule Bonfire.Boundaries.RuntimeConfig do
  @behaviour Bonfire.Common.ConfigModule
  def config_module, do: true

  use Bonfire.Common.Localise

  @doc """
  NOTE: you can override this default config in your app's runtime.exs, by placing similarly-named config keys below the `Bonfire.Common.Config.LoadExtensionsConfig.load_configs` line
  """
  def config do
    import Config

    # Which query shape `boundarise` uses for the :see/:read check (see
    # `Bonfire.Boundaries.Queries.boundarise_query/6`). Only set when the env var is
    # present so it doesn't override per-env config (e.g. test.exs) with a default.
    case System.get_env("BOUNDARISE_STRATEGY") do
      "direct_exists" ->
        config :bonfire, Bonfire.Boundaries, boundarise_strategy: :direct_exists

      "view" ->
        config :bonfire, Bonfire.Boundaries, boundarise_strategy: :view

      "summary_subquery" ->
        config :bonfire, Bonfire.Boundaries, boundarise_strategy: :summary_subquery

      _ ->
        nil
    end

    ### Verbs are like permissions. Each represents some activity or operation that may or may not be able to perform.
    verbs = [
      request: %{
        id: "1NEEDPERM1SS10NT0D0TH1SN0W",
        verb: l("Request"),
        icon: "humbleicons:user-asking",
        summary: l("Request permission for another verb (eg. request to follow)")
      },
      see: %{
        id: "0BSERV1NG11ST1NGSEX1STENCE",
        verb: l("See"),
        icon: "ph:eyes-duotone",
        summary: l("Discoverable in lists (like feeds)")
      },
      read: %{
        id: "0EAD1NGSVTTER1YFVNDAMENTA1",
        verb: l("Read"),
        icon: "ph:read-cv-logo-duotone",
        summary: l("Readable/visible (if you can see or have a direct link)")
      },
      bookmark: %{
        id: "1B00KMARKMYGREATESTF1ND1NG",
        verb: l("Bookmark"),
        icon: "ph:bookmark-duotone",
        summary: l("Bookmark an object (only visible to you)")
      },
      like: %{
        id: "11KES1ND1CATEAM11DAPPR0VA1",
        verb: l("Like"),
        icon: "ph:fire-duotone",
        summary: l("Like an object (and notify the author)")
      },
      boost: %{
        id: "300ST0R0RANN0VCEANACT1V1TY",
        verb: l("Boost"),
        icon: "ph:arrows-counter-clockwise-duotone",
        summary: l("Boost an object (and notify the author)")
      },
      flag: %{
        id: "71AGSPAM0RVNACCEPTAB1E1TEM",
        verb: l("Flag"),
        icon: "ph:flag-duotone",
        summary:
          l(
            "Flag an object for a moderator to review (please note that anyone who can see or read something can flag it anyway)"
          )
      },
      reply: %{
        id: "71TCREAT1NGA11NKEDRESP0NSE",
        verb: l("Reply"),
        icon: "ph:chat-circle-duotone",
        summary: l("Reply to an activity or post")
      },
      quote: %{
        id: "2QV0TE1SH1GHF0RM0FF1ATTERY",
        verb: l("Quote"),
        icon: "ph:quotes-duotone",
        summary: l("Quote a post or activity")
      },
      annotate: %{
        id: "110VET0ANN0TATEEVERYTH1NGS",
        verb: l("Annotate"),
        icon: "ph:quotes-duotone",
        summary: l("Annotate a video or other content")
      },
      mention: %{
        id: "0EFERENC1NGTH1NGSE1SEWHERE",
        verb: l("Mention"),
        icon: "ph:at-duotone",
        summary: l("Mention a user or object (and notify them)")
      },
      message: %{
        id: "40NTACTW1THAPR1VATEMESSAGE",
        verb: l("Message"),
        icon: "ph:envelope-duotone",
        summary: l("Send a message")
      },
      tag: %{
        id: "4ATEG0R1S1NGNGR0VP1NGSTVFF",
        verb: l("Tag"),
        icon: "ph:tag-duotone",
        summary: l("Tag a user or object, or publish in a topic")
      },
      label: %{
        id: "7PDATETHESTATVS0FS0METH1NG",
        verb: l("Label"),
        icon: "ph:tag-simple-duotone",
        summary: l("Set/update a status or label")
      },
      follow: %{
        id: "20SVBSCR1BET0THE0VTPVT0F1T",
        verb: l("Follow"),
        icon: "ph:eye-duotone",
        summary: l("Follow a user or thread or whatever")
      },
      join: %{
        id: "50J01NAGR0VP0RC0MMVN1TYYYY",
        verb: l("Join"),
        icon: "ph:door-open-duotone",
        summary: l("Join a group or community as a member")
      },
      schedule: %{
        id: "7SCHEDV1EF1XEDDES1REDDATES",
        verb: l("Schedule"),
        icon: "ph:calendar-plus-duotone",
        summary: l("Set an expected or desired date")
      },
      pin: %{
        id: "1P1NN1NNG1S11KEH1GH11GHT1T",
        verb: l("Pin"),
        icon: "ph:map-pin-simple-duotone",
        summary: l("Pin something to highlight it")
      },
      create: %{
        id: "4REATE0RP0STBRANDNEW0BJECT",
        verb: l("Create"),
        icon: "ph:plus-circle-duotone",
        summary: l("Create a post or other object")
      },
      edit: %{
        id: "4HANG1NGVA1VES0FPR0PERT1ES",
        verb: l("Edit"),
        icon: "ph:pencil-simple-line-duotone",
        summary: l("Modify the contents of an existing object")
      },
      delete: %{
        id: "4AKESTVFFG0AWAYPERMANENT1Y",
        verb: l("Delete"),
        icon: "ph:trash-duotone",
        summary: l("Delete an object")
      },
      vote: %{
        id: "7V0TEMEANSC0NSENT0RREFVSA1",
        verb: l("Vote"),
        icon: "material-symbols:how-to-vote",
        summary: l("Vote on something")
      },

      # WIP adding verbs, see: https://github.com/bonfire-networks/bonfire-app/issues/406

      toggle: %{
        id: "1CANENAB1E0RD1SAB1EFEATVRE",
        verb: l("Toggle"),
        icon: "ph:toggle-right-duotone",
        summary: l("Enable/disable extensions or features"),
        scope: :instance
      },
      describe: %{
        id: "1CANADD0M0D1FY1NF0METADATA",
        verb: l("Describe"),
        icon: "ph:pen-duotone",
        summary: l("Edit info and metadata, eg. thread titles"),
        scope: :instance
      },
      grant: %{
        id: "1T0ADDED1TREM0VEB0VNDAR1ES",
        verb: l("Grant"),
        icon: "ph:key-duotone",
        summary: l("Add, edit or remove boundaries"),
        scope: :instance
      },
      assign: %{
        id: "1T0ADDC1RC1ES0RASS1GNR01ES",
        verb: l("Assign"),
        icon: "ph:identification-card-duotone",
        summary: l("Assign roles or tasks"),
        scope: :instance
      },
      invite: %{
        id: "11NV1TESPE0P1E0RGRANTENTRY",
        verb: l("Invite"),
        icon: "ph:gift-duotone",
        summary: l("Join without invitation and invite others"),
        scope: :instance
      },
      mediate: %{
        id: "1T0SEEF1AGSANDMAKETHEPEACE",
        verb: l("Mediate"),
        icon: "ph:circles-three-duotone",
        summary: l("See flags"),
        scope: :instance
      },
      block: %{
        id: "1T0MANAGEB10CKGH0STS11ENCE",
        verb: l("Block"),
        icon: "ph:prohibit-duotone",
        summary: l("Manage blocks"),
        scope: :instance
      },
      configure: %{
        id: "1T0C0NF1GVREGENERA1SETT1NG",
        verb: l("Configure"),
        icon: "ph:sliders-duotone",
        summary: l("Change general settings"),
        scope: :instance
      }
    ]

    all_verb_names = Enum.map(verbs, &elem(&1, 0))

    default_verbs_for = [
      objects: [
        :request,
        :see,
        :read,
        :like,
        :boost,
        :reply,
        :quote,
        # :annotate,
        # :tag,
        # :label,
        :vote,
        # :grant,
        :edit,
        :delete
      ]
    ]

    preferred_verb_order =
      default_verbs_for[:objects] ++
        [
          :create,
          :mention,
          :message,
          :follow,
          :join,
          :pin,
          :schedule,
          :vote,
          :toggle,
          :describe,
          :grant,
          :assign,
          :invite,
          :mediate,
          :block,
          :configure
        ]

    # make sure all_verb_names lists the ordered ones first, in the preferred order
    all_verb_names =
      preferred_verb_order ++
        (all_verb_names -- preferred_verb_order)

    # |> IO.inspect()
    verbs_negative = fn verbs ->
      Enum.reduce(verbs, %{}, &Map.put(&2, &1, false))
    end

    verbs_basics = [:bookmark, :flag]

    # The bottom of the cumulative ladder `role_verbs_interact` and friends build on, and the `read` role's exact verb list.
    # `:request` is deliberately NOT here. Asking is granted where it is MEANT (`everyone_may_request`), never as a side effect of being allowed to read — otherwise an invite-only group or a moderators-only channel invites requests it will never grant.
    verbs_see_read_basics = [:read, :see] ++ verbs_basics

    verbs_liking = [:like]
    verbs_sharing = [:boost]

    # `:join` is NOT here, for the same reason `:request` is not in `verbs_see_read_basics`: it is a MEMBERSHIP verb, and leaving it in a participation bundle meant `participation: "anyone"` granted it to every local whatever the membership dimension said. It is granted only by `locals_may_join` and `everyone_may_join`.
    verbs_partake = [:vote]
    verbs_ping = [:reply, :mention, :message]
    verbs_critique = [:quote]
    verbs_curate = [:tag, :describe, :annotate, :pin]
    verbs_contrib = [:create, :tag, :describe, :annotate]
    verbs_edit = [:edit, :tag, :describe, :annotate]
    verbs_mod = [:invite, :label, :mediate, :block, :delete]

    # verbs_interact_minus_follow =
    #   verbs_see_read_basics ++ [:like]

    verbs_interact_minus_boost = verbs_see_read_basics ++ verbs_liking
    verbs_interact_minus_like = verbs_see_read_basics ++ verbs_sharing

    # like + bookmark + flag + vote — quiet reactions that don't amplify reach (safe for unlisted/quiet content)
    verbs_react_quiet = verbs_liking ++ [:bookmark, :flag]

    # like + boost + bookmark + flag + vote — full reactions including amplification (for discoverable/preview content)
    verbs_react = verbs_react_quiet ++ verbs_sharing

    # `:follow` is NOT in the role ladder. While it was here, every role from `interact` up handed it out, so a user's `SELF` ACLs (`locals_may_reply`, `remotes_may_participate`) always granted following and "follows need approval" could only be said by taking it back, which is what `no_follow` was for. Granted positively instead, by `everyone_may_follow` for people and by each group's visibility signature.
    role_verbs_interact =
      verbs_see_read_basics ++ verbs_liking ++ verbs_sharing

    # verbs_participate_message_minus_follow =
    #   verbs_interact_minus_follow ++ verbs_ping

    verbs_participate_on_message = verbs_interact_minus_boost ++ verbs_ping

    role_verbs_participate = role_verbs_interact ++ verbs_ping ++ verbs_partake

    role_verbs_critique = role_verbs_participate ++ verbs_critique

    role_verbs_curate = role_verbs_critique ++ verbs_curate

    role_verbs_editor = role_verbs_curate ++ verbs_edit

    role_verbs_contribute = role_verbs_curate ++ verbs_contrib

    role_verbs_editor_and_contribute = role_verbs_editor ++ verbs_contrib

    # verbs_join_and_contribute = role_verbs_contribute ++ [:invite]

    # `:edit` so group admins/moderators can edit the object they moderate (e.g. a group's profile & images)
    role_verbs_moderate = role_verbs_contribute ++ [:edit] ++ verbs_mod

    # Builds a `cannot_*` rung: deny every verb except the ones in the rung below.
    # `:request` is always kept, which is the ladder's floor: however denied someone is, they may still ask to follow or join. Taking that away too is a separate decision, so it gets its own role (`cannot_participate_or_request`) rather than being folded in here. `cannot_anything` is the other exception: it bypasses this and denies everything.
    cannot_except = fn keep ->
      Enum.reject(all_verb_names, fn v -> v in keep or v == :request end)
    end

    # preset ACLs to show when editing boundaries
    basic_acls = [
      :everyone_may_see_read,
      :remotes_may_interact,
      :remotes_may_participate,
      :locals_may_interact,
      :locals_may_reply
    ]

    config :bonfire,
      verbs: verbs,
      preferred_verb_order: all_verb_names,
      default_verbs_for: default_verbs_for,
      role_verbs: %{
        none: %{read_only: true, label: l("None")},
        read: %{can_verbs: verbs_see_read_basics, read_only: true, label: l("Read")},
        react: %{can_verbs: verbs_interact_minus_boost, read_only: true, label: l("React")},
        share: %{can_verbs: verbs_interact_minus_like, read_only: true, label: l("Share")},
        interact: %{
          can_verbs: role_verbs_interact,
          read_only: true,
          label: l("Fully visible"),
          description: l("Can see, read, and interact with content"),
          icon: "ph:eye-duotone"
        },
        # see + react (no read) — for preview visibility
        discover: %{
          can_verbs: [:see] ++ verbs_react,
          read_only: true,
          label: l("Discoverable"),
          description: l("Can see the group exists and react, but not read content"),
          icon: "fluent:globe-search-24-regular"
        },
        # read + quiet react (no see, no boost) — for unlisted visibility
        unlisted_read: %{
          can_verbs: [:read] ++ verbs_react_quiet,
          read_only: true,
          label: l("Unlisted"),
          description: l("Can read with a direct link but not found in listings or feeds"),
          icon: "ph:link-simple-duotone"
        },
        participate: %{
          can_verbs: role_verbs_participate,
          read_only: true,
          label: l("Participate")
        },
        critique: %{can_verbs: role_verbs_critique, read_only: true, label: l("Critique")},
        curate: %{can_verbs: role_verbs_curate, read_only: true, label: l("Curate")},
        edit: %{can_verbs: role_verbs_editor, read_only: true, label: l("Edit")},
        contribute: %{
          usage: :ops,
          can_verbs: role_verbs_contribute,
          read_only: true,
          label: l("Contribute")
        },
        moderate: %{
          usage: :ops,
          can_verbs: role_verbs_moderate,
          read_only: false,
          label: l("Moderate")
        },
        administer: %{can_verbs: all_verb_names, read_only: true, label: l("Administer")},
        # the only rung with no `:request` floor — it denies asking along with everything else
        cannot_anything: %{
          cannot_verbs: all_verb_names,
          read_only: true,
          label: l("Cannot do anything, not even ask")
        },
        cannot_request: %{cannot_verbs: [:request], read_only: true, label: l("Cannot request")},
        cannot_discover: %{
          cannot_verbs: cannot_except.([:read]),
          read_only: true,
          label: l("Cannot discover")
        },
        cannot_read: %{
          cannot_verbs: cannot_except.([]),
          read_only: true,
          label: l("Cannot do anything except ask")
        },
        cannot_react: %{
          cannot_verbs: cannot_except.(verbs_interact_minus_like),
          read_only: true,
          label: l("Cannot react")
        },
        cannot_share: %{
          cannot_verbs: cannot_except.(verbs_interact_minus_boost),
          read_only: true,
          label: l("Cannot share")
        },
        cannot_interact: %{
          cannot_verbs: cannot_except.(verbs_see_read_basics),
          read_only: true,
          label: l("Cannot interact")
        },
        cannot_participate: %{
          cannot_verbs: cannot_except.(role_verbs_interact),
          read_only: true,
          label: l("Cannot participate")
        },
        # `cannot_participate` plus the floor: for where the asking itself is the problem, such as an announcement channel nobody may petition to post in
        cannot_participate_or_request: %{
          cannot_verbs: Enum.reject(all_verb_names, fn v -> v in role_verbs_interact end),
          read_only: true,
          label: l("Cannot participate or ask")
        },
        cannot_critique: %{
          cannot_verbs: cannot_except.(role_verbs_participate),
          read_only: true,
          label: l("Cannot critique")
        },
        cannot_curate: %{
          cannot_verbs: cannot_except.(role_verbs_critique),
          read_only: true,
          label: l("Cannot curate")
        },
        cannot_contribute: %{
          usage: :ops,
          cannot_verbs: cannot_except.(role_verbs_curate),
          read_only: true,
          label: l("Cannot contribute")
        },
        cannot_administer: %{
          cannot_verbs: cannot_except.(role_verbs_editor_and_contribute),
          read_only: true,
          label: l("Cannot administer")
        }
      },
      role_to_grant: [
        default: :participate
      ],
      verbs_to_grant: [
        default: role_verbs_participate,
        message: verbs_participate_on_message
      ],
      # preset ACLs to show when editing boundaries
      acls_for_dropdown: basic_acls,
      # what boundaries we can display to everyone when applied on objects
      public_acls_on_objects:
        basic_acls ++
          [
            :everyone_may_see,
            :everyone_may_read,
            # :everyone_may_see_read,
            :guests_may_see,
            :guests_may_read,
            :guests_may_see_read,
            :locals_may_read_interact,
            :locals_may_read_reply
          ],
      #  used for setting boundaries — slug → ACL atoms applied at create time.
      #  Slug namespaces:
      #    - General object boundaries (posts/single-dim): "public", "unlisted", "local", "private"
      #    - Group membership: "open", "local:members", "archipelago:members", "on_request", "invite_only"
      #    - Group participation: "anyone", "archipelago:contributors", "local:contributors", "group_members", "moderators"
      #    - Group visibility: "global", "nonfederated", "nonfederated:{preview,unlisted}",
      #      "archipelago", "local", "local:{preview,unlisted}", "preview", "unlisted",
      #      "members:private"
      #    - Default content visibility: visibility slugs above plus "{public,local,nonfederated}:{quiet,preview}"
      #  Slugs not listed below have no ACL signature (members/moderators circle controlled, or open by default).
      preset_acls: %{
        # --- General object boundaries (single-dim) ---
        "public" => [
          :everyone_may_see_read,
          :locals_may_reply,
          :remotes_may_participate,
          # asking to quote is on by default: `Quotes.check_quote_permission/3` reads `:request` on the quoted post to tell "ask the author" from "not allowed at all". `:request` is granted positively rather than riding along with `:read`, so a post needs it named here, as these single-dim presets are for posts what the membership dimension is for groups.
          :everyone_may_request
        ],
        # `:locals_may_follow` for the same reason as `nonfederated` below: the other ACL here grants a ROLE, and `:follow` no longer rides in one. Harmless on the post side of this shared key, where following is meaningless.
        "local" => [:locals_may_reply, :everyone_may_request, :locals_may_follow],
        "private" => [],

        # --- Membership presets ---
        # `open` historically bundled the participation ACLs (`*_may_contribute`) too, but those belong to participation slugs (`anyone` / `local:contributors`), keeping them here would mis-detect any anyone-participation group as `open` membership. The form cascades `open` → `participation: anyone` so the contributes still get applied via the participation slug.
        # `:request` is granted by the MEMBERSHIP dimension and nowhere else. It is one verb for all asking, so it needs a single home, and the ACL's own name says which one ("Everyone may request (eg. to join)"). Every membership value that means yes grants it; `invite_only` grants nothing, which is how an announcement channel (`invite_only` + `moderators` participation) ends up offering no ask at all, by omission rather than by a negative rule anyone had to write.
        "open" => [:everyone_may_see_read, :everyone_may_join, :everyone_may_request],
        "local:members" => [:locals_may_join, :everyone_may_request],
        # ARCHIPELAGO slugs are commented out across all four dimensions until the grants exist.
        # Not because archipelago is unbuilt (it ships, as a federation mode): what is unbuilt is a group carrying its OWN allow-list. With the instance in archipelago mode, federating already means federating to the archipelago, so `global` and `nonfederated` cover it.
        # They were listed here with `[]`, which is worse than absent for a slug that grants nothing YET: an empty signature cannot be detected, so `archipelago:members` read back as `invite_only` and `archipelago:contributors` as `group_members`, reporting rules no group was given. Restore these together with the ACLs that make them mean something.
        # "archipelago:members" => [],
        # reviewing entry is a MEMBERSHIP rule, so it grants the asking and withholds `:join`, and says nothing about following: whether someone may subscribe to the group's feed is the visibility dimension's answer. Mobilizon states the same pair on the wire, `manuallyApprovesFollowers: false` alongside `openness: "moderated"`.
        "on_request" => [:everyone_may_request],
        # circle-controlled: no global grants, written as an explicit `[]`. EVERY slug a group can hold needs an entry here, including the ones that grant nothing: this map is what makes a slug passable as `to_boundaries`, so a slug listed with `[]` is applied and grants nothing, while one that is absent is treated as an ACL id by `boundaries_normalise_direct/1`.
        "invite_only" => [],

        # --- Participation presets  ---
        "anyone" => [:locals_may_contribute, :remotes_may_contribute],
        # see the archipelago note under the membership presets above
        # "archipelago:contributors" => [],
        "local:contributors" => [:locals_may_contribute],
        # circle-controlled, no global grants. see the note on `invite_only` above
        "group_members" => [],
        "moderators" => [],

        # --- Group visibility presets ---
        # full (see+read+interact): global disabled until groups federation ships
        "global" => [:everyone_may_see_read_interact],
        # see the archipelago note under the membership presets above "archipelago" => [],
        # nonfederated: the non-federated equivalent of "public": guests see+read, locals get full participation (incl. reply/mention/message), AP-deny applied in Classify.Boundaries. Mirrors `public`/`local` (which grant `:locals_may_reply`) minus the federation reach, so a public-on-instance community's posts are replyable by locals, not capped at read-only interact.
        # `:locals_may_follow` is explicit here because the other ACL in this signature grants a ROLE, and `:follow` no longer rides in one. The visibility slugs whose ACLs list verbs directly (`*_see_interact`, `*_read_interact`, …) already splice `[:follow]` themselves.
        "nonfederated" => [:guests_may_see_read, :locals_may_reply, :locals_may_follow],
        "nonfederated:preview" => [:guests_may_see, :locals_may_see_interact],
        "nonfederated:unlisted" => [:guests_may_read, :locals_may_read_reply],
        "members:private" => [],
        # unlisted (readable via direct link, not listed). The two `*_may_read_reply` ACLs are what its `nonfederated:` and `local:` siblings already grant and this one was missing: they add `verbs_ping`, so someone who can already read an unlisted thing can reply to, mention and message it. Without them an unlisted POST would be one nobody could answer. Granted to remotes as well as locals, since a post reached by link is reached the same way from either side. Safe to add rather than backfill because the slug has never been selectable (see its `disabled:` below), so no object holds it.
        "unlisted" => [
          :everyone_may_read_interact,
          :locals_may_read_reply,
          :remotes_may_read_reply
        ],
        # "archipelago:unlisted" => [],
        "local:unlisted" => [:locals_may_read_reply],
        # preview (see+react, but :read for members only — granted in Classify.Boundaries). Called `discoverable` until 2026-09-16: that name said only half of what the slug means, since being findable is compatible with being readable and that was confusing. The DCV dimension already called this `preview`, with identical grants, so the scoped ones below are now the same entries rather than twins.
        "preview" => [:everyone_may_see_interact],
        # "archipelago:preview" => [],
        "local:preview" => [:locals_may_see_interact],

        # --- Default content visibility (DCV) presets ---
        # Uses some visibility slugs as-is ("public", "local", "nonfederated", "members:private") plus :quiet (readable + reply, no boost) and :preview (see-only) variants.
        # `nonfederated:preview`, `local:preview`, `nonfederated:unlisted` and `local:unlisted` are declared once, up in the visibility block: both dimensions want the same grants, and one flat map cannot hold a key twice. `nonfederated:quiet` and `local:quiet` were those same two signatures under a second name, so they are gone rather than renamed.
        # `public:quiet` was this role's global-scope entry for posts, and is now `unlisted` as well: it only ever differed by the `verbs_ping` grant that `unlisted` was missing, which is the one thing a post in this tier actually needs. So `quiet` is gone as a vocabulary, and each scope names this role once for both dimensions.
        # "archipelago:quiet" => [],
        "public:preview" => [:everyone_may_see_interact]
      },
      # Used for back-translating saved boundaries to a preset slug, for single-dim
      # objects (posts). Group dimension detection uses :group_dim_acls below.
      # Matcher entries can be wider than the applier above (legacy/synonym ACLs).
      preset_acls_match: %{
        # TODO: derive from :preset_acls above.
        "public" => [
          :everyone_may_see,
          :everyone_may_read,
          :everyone_may_see_read,
          :remotes_may_interact,
          :remotes_may_participate,
          :remotes_may_reply_follow_join_request
        ],
        "unlisted" => [
          :everyone_may_read_interact,
          :locals_may_read_reply,
          :remotes_may_read_reply
        ],
        # the `*_follow_join_request` / `*_request` entries are the DEPRECATED ACLs, listed so objects created before those ACLs were versioned still back-translate to the same preset. This is what "matcher entries can be wider than the applier" is for.
        "local" => [
          :locals_may_read_interact,
          :locals_may_read_reply,
          :locals_may_interact,
          :locals_may_reply,
          :locals_may_reply_follow_join_request
        ],
        "local:unlisted" => [:locals_may_read_interact, :locals_may_read_reply],
        "local:preview" => [:locals_may_see_interact],
        "preview" => [:everyone_may_see_interact],
        "global" => [:everyone_may_see_read_interact],
        "nonfederated" => [
          :guests_may_see_read,
          :guests_may_see_read_request,
          :locals_may_reply,
          :locals_may_reply_follow_join_request
        ],
        "nonfederated:preview" => [
          :guests_may_see,
          :guests_may_see_request,
          :locals_may_see_interact
        ],
        "nonfederated:unlisted" => [
          :guests_may_read,
          :guests_may_read_request,
          :locals_may_read_interact,
          :locals_may_read_reply
        ]
      }

    # NOTE: per-dimension ACL signatures for group back-translation are derived at
    # runtime from `:preset_acls` + `:preset_dimensions[dim][:slug_order]` by
    # `Bonfire.Boundaries.Presets.dim_acls/0`. Don't reintroduce a hand-maintained
    # `:group_dim_acls` config — it drifts.

    # Scope metadata for the two-level boundary selector UI (visibility + DCV dims).
    # Each scope maps to label/icon/disabled status; the actual ACL grants are in preset_acls above.
    config :bonfire_boundaries,
      scopes: %{
        global: %{
          label: l("Public (federated)"),
          description: l("Visible to everyone including the wider fediverse"),
          icon: "ph:globe-duotone",
          disabled: l("Coming soon: requires groups federation")
        },
        nonfederated: %{
          label: l("Public"),
          description: l("Visible on this instance but not sent to the wider fediverse"),
          icon: "ph:house-line-duotone"
        },
        archipelago: %{
          label: l("Archipelago"),
          description: l("Visible to users on trusted linked instances"),
          icon: "ph:planet-duotone",
          disabled: l("Coming soon: requires archipelago feature")
        },
        local: %{
          label: l("Local"),
          description: l("Visible only to users on this instance"),
          icon: "ph:campfire-duotone"
        },
        members: %{
          label: l("Members only"),
          description: l("Visible only to group members"),
          icon: "ph:users-three-duotone"
        }
      }

    # create_verbs: [
    #   # block:  Bonfire.Data.Social.Block,
    #   boost: Bonfire.Data.Social.Boost,
    #   follow: Bonfire.Data.Social.Follow,
    #   flag: Bonfire.Data.Social.Flag,
    #   like: Bonfire.Data.Social.Like
    # ],

    ### Now follows quite a lot of fixtures that must be inserted into the database.

    config :bonfire_boundaries,
      ### Users are placed into one or more circles, either by users or by the system. Circles referenced in ACLs have the
      ### effect of applying to all users in those circles.
      circles: [
        ### Public circles used to categorise broadly how much of a friend/do the user is.
        guest: %{
          id: "0AND0MSTRANGERS0FF1NTERNET",
          name: l("Anyone on the internet"),
          icon: "ph:globe-hemisphere-east-duotone"
        },
        local: %{
          id: "3SERSFR0MY0VR10CA11NSTANCE",
          name: l("Local users"),
          icon: "ph:map-pin-line-duotone"
        },
        activity_pub: %{
          id: "7EDERATEDW1THANACT1V1TYPVB",
          name: l("Anyone in the fediverse"),
          icon: "ph:fediverse-logo-duotone"
        },
        # Feed origin×boundary buckets for write-time feed addressing (see the local-remote-feeds plan). These are `feed_publish.feed_id` pointers seeded like the feed circles above, NOT member circles — nobody joins them, they carry no ACL grants, and they shouldn't appear in circle-picker UIs. The `_custom` buckets reuse the legacy feed ids via `Feeds.named_feed_id/1` aliases (`local_custom`=`local`/`3SERS…`, `remote_custom`=`activity_pub`/`7EDER…`), so only these 3 are new.
        local_public: %{
          id: "7PVB11C0BJECTFR0M10CA1VSER",
          name: l("Local public activities"),
          icon: "ph:map-pin-duotone"
        },
        local_instance_only: %{
          id: "710CA10BJ0N1YF0R10CA1VSERS",
          name: l("Local instance-only activities"),
          icon: "ph:house-line-duotone"
        },
        remote_public: %{
          id: "7PVB11C0BJFR0MAREM0TEACT0R",
          name: l("Remote public activities"),
          icon: "ph:planet-duotone"
        },
        admin: %{
          id: "0ADM1NSVSERW1THSVPERP0WERS",
          name: l("Instance Admins"),
          icon: "ph:hard-hat-duotone"
        },
        mod: %{
          id: "10VE1YM0DSHE1PHEA1THYC0MMS",
          name: l("Instance Moderators"),
          icon: "ph:shield-plus-duotone"
        },
        suggested_profiles: %{
          id: "5VGGESTEDPR0F11EST0F0110WS",
          name: l("Suggested Profiles"),
          icon: "ph:users-three-duotone"
        },

        ### Stereotypes - placeholders for special per-user circles the system will manage.
        followers: %{
          id: "7DAPE0P1E1PERM1TT0F0110WME",
          name: l("People who follow me"),
          stereotype: true,
          icon: "ph:broadcast-duotone"
        },
        followed: %{
          id: "4THEPE0P1ES1CH00SET0F0110W",
          name: l("People I am following"),
          stereotype: true,
          icon: "ph:address-book-duotone"
        },
        ghost_them: %{
          id: "7N010NGERC0NSENTT0Y0VN0WTY",
          name: l("People I am ghosting"),
          stereotype: true
        },
        silence_them: %{
          id: "7N010NGERWANTT011STENT0Y0V",
          name: l("People I am silencing"),
          stereotype: true
        },
        allow_them: %{
          id: "3TRVSTTHESED0MA1NS0RACT0RS",
          name: l("Instances and actors I allow to federate with me"),
          stereotype: true
        },
        silence_me: %{
          id: "0KF1NEY0VD0N0TWANTT0HEARME",
          name: l("People silencing me"),
          stereotype: true
        }
      ],
      ### ACLs (Access Control Lists) are reusable lists of permissions assigned to users and circles. Objects in bonfire
      ### have one or more ACLs attached and we combine the results of all of them to determine whether a user is permitted
      ### to perform a particular operation.
      acls: [
        instance_care: %{
          id: "01SETT1NGSF0R10CA11NSTANCE",
          name: l("Local instance roles & boundaries")
        },
        mods_may_manage: %{
          id: "1M0DERAT0RSADM1NSMAYMANAGE",
          name: l("Moderators may manage")
        },

        ### Public ACLs that allow basic control over visibility and interactions.
        everyone_may_see_read: %{
          id: "1EVERY0NEMAYSEEEEANDREADDD",
          name: l("Everyone may see and read")
        },
        everyone_may_read: %{
          id: "2EVERY0NEMAYREADDDDDDDDDDD",
          name: l("Everyone may read")
        },
        everyone_may_see: %{
          id: "3EVERY0NEMAYSEEEEEEEEEEEEE",
          name: l("Everyone may read")
        },
        # ⚠️ The six `*_deprecated`-flagged ACLs below keep the ORIGINAL ids while their live namesakes take new ones. `:request` left the read bundles and `:join` left `verbs_partake`, but grants are upserted and never pruned (`Scaffold.Instance.upsert_grants_helper/1`), so every existing row still grants both. Editing those rows in place was not an option: preset ACLs are global fixtures, so a post from last year points at the same row as one created tomorrow. Versioning instead leaves existing objects exactly as they are and lets the group `DataMigration` re-point only groups. `fixtures/0` skips anything `deprecated`, so a fresh install never creates them.
        guests_may_see_read: %{
          id: "7W1DE1YAVA11AB1ET0SEEREAD2",
          name: l("Publicly discoverable and readable")
        },
        guests_may_see_read_request: %{
          id: "7W1DE1YAVA11AB1ET0SEENREAD",
          name: l("Publicly discoverable and readable, and may request more access"),
          deprecated: true
        },
        guests_may_see: %{
          id: "50VCANF1NDMEBVTCAN0T0PEN22",
          name: l("Publicly discoverable, contents may be hidden")
        },
        guests_may_see_request: %{
          id: "50VCANF1NDMEBVTCAN0T0PENME",
          name: l("Publicly discoverable, contents may be hidden, and may request more access"),
          deprecated: true
        },
        guests_may_read: %{
          id: "50VCANREAD1FY0VHAVETHE1122",
          name: l("Publicly readable, but not necessarily discoverable")
        },
        guests_may_read_request: %{
          id: "50VCANREAD1FY0VHAVETHE11NK",
          name:
            l("Publicly readable (but not necessarily discoverable), and may request more access"),
          deprecated: true
        },
        remotes_may_interact: %{
          id: "5REM0TEPE0P1E1NTERACTREACT",
          name: l("Remote actors may read and interact")
        },
        remotes_may_participate: %{
          id: "5REM0TEPE0P1E1NTERACTREP12",
          name: l("Remote actors may read, interact and reply")
        },
        # versioned because this ACL is in every user's SELF controlleds and grants the `participate` ROLE, which used to carry `:follow`. A legacy row would let a remote actor follow a `request_before_follow` account outright, bypassing the review it asked for.
        remotes_may_reply_follow_join_request: %{
          id: "5REM0TEPE0P1E1NTERACTREP1Y",
          name: l("Remote actors may read, interact, reply, follow, join and ask for more"),
          deprecated: true
        },
        remotes_may_contribute: %{
          id: "7REM0TEACT0RSCANC0NTR1BV22",
          name: l("Remote actors may contribute")
        },
        remotes_may_contribute_follow_join_request: %{
          id: "7REM0TEACT0RSCANC0NTR1BVTE",
          name: l("Remote actors may contribute, join and ask for more"),
          deprecated: true
        },
        locals_may_read_interact: %{
          id: "10CA1SMAYSEEANDREAD0N1YN0W",
          name: l("Visible to local users")
        },
        locals_may_read_reply: %{
          id: "10CA1SMAYREADREP1YN0B00ST7",
          name: l("Local users may read, reply and interact (but not boost)")
        },
        remotes_may_read_reply: %{
          id: "5REM0TESMAYREADREP1YN0B00T",
          name: l("Remote actors may read, reply and interact (but not boost)")
        },
        locals_may_interact: %{
          id: "710CA1SMY1NTERACTN0TREP1YY",
          name: l("Local users may read and interact")
        },
        locals_may_reply: %{
          id: "710CA1SMY1NTERACTANDREP122",
          name: l("Local users may read, interact and reply")
        },
        locals_may_reply_follow_join_request: %{
          id: "710CA1SMY1NTERACTANDREP1YY",
          name: l("Local users may read, interact, reply, join and ask for more"),
          deprecated: true
        },
        locals_may_contribute: %{
          id: "1ANY10CA1VSERCANC0NTR1BV22",
          name: l("Local users may contribute")
        },
        locals_may_contribute_follow_join_request: %{
          id: "1ANY10CA1VSERCANC0NTR1BVTE",
          name: l("Local users may contribute, join and ask for more"),
          deprecated: true
        },
        locals_may_see: %{
          id: "10CA1SMAYSEEEEEEEEEEEEEN0W",
          name: l("Local users may see")
        },
        locals_may_follow: %{
          id: "10CA1SMAYF0110WWWWWWWWWWWW",
          name: l("Local users may follow")
        },
        locals_may_join: %{
          id: "10CA1SMAYJ01NNNNNNNNNNNNNN",
          name: l("Local users may join")
        },
        everyone_may_join: %{
          id: "3EVERY0NEMAYJ01NNNNNNNNNNN",
          name: l("Everyone may join")
        },
        everyone_may_follow: %{
          id: "3EVERY0NEMAYF0110WWWWWWWWW",
          name: l("Everyone may follow")
        },
        everyone_may_request: %{
          id: "3EVERY0NEMAYREQVEST1111111",
          name: l("Everyone may request (eg. to join)")
        },
        everyone_may_see_interact: %{
          id: "3EVERY0NEMAYSEEE1NTERACTYY",
          name: l("Everyone may see and interact (but not read)")
        },
        locals_may_see_interact: %{
          id: "10CA1SMAYSEEE1NTERACTYYYYY",
          name: l("Local users may see and interact (but not read)")
        },
        everyone_may_read_interact: %{
          id: "3EVERY0NEMAYREAD1NTERACTYY",
          name: l("Everyone may read and react (but not boost or discover)")
        },
        everyone_may_see_read_interact: %{
          id: "3EVERY0NEMAYSEREAD1NTERACT",
          name: l("Everyone may see, read and interact")
        },
        locals_may_see_read_interact: %{
          id: "10CA1SMAYSEREAD1NTERACTYYY",
          name: l("Local users may see, read and interact")
        },
        followed_may_reply: %{
          id: "1HANDP1CKEDZEPE0P1E1F0110W",
          name: l("People who I follow may read, interact, and reply"),
          stereotype: true
        },

        ### Stereotypes - placeholders for special per-user (or per-object) ACLs the system will manage.

        custom_acl: %{
          id: "7HECVST0MAC1F0RAN0BJECTETC",
          name: l("Custom boundary"),
          stereotype: true
        },

        ## ACLs that confer my personal permissions on things i have created
        # i_may_read:            %{id: "71MAYSEEANDREADMY0WNSTVFFS", name: l("I may read")},              # not currently used
        # i_may_interact:        %{id: "71MAY1NTERACTW1MY0WNSTVFFS", name: l("I may read and interact")}, # not currently used
        i_may_administer: %{
          id: "71MAYADM1N1STERMY0WNSTVFFS",
          name: l("I may administer"),
          stereotype: true
        },

        ## ACLs that confer permissions for people i mention (or reply to, which causes a mention)
        # mentions_may_read:     %{id: "7MENT10NSCANREADTH1STH1NGS", name: l("Mentions may read"), stereotype: true},
        # mentions_may_interact: %{id: "7MENT10NSCAN1NTERACTW1TH1T", name: l("Mentions may read and interact"), stereotype: true},
        # mentions_may_reply:    %{id: "7MENT10NSCANEVENREP1YT01TS", name: l("Mentions may read, interact and reply"), stereotype: true},

        ## "Negative" ACLs

        # Deprecated now that `:follow` has one home and maually-reviewed follows is by not including a grant (`everyone_may_request` instead of `everyone_may_follow`) rather than a denial added on top. Kept in config so existing rows still resolve by id, and excluded from fixtures so no new object attaches to it. Nothing applies it any more.
        no_follow: %{
          id: "1MVSTREQVESTBEF0REF0110W1N",
          name: l("People must request to follow"),
          deprecated: true
        },

        # Apply overrides for ghosting and silencing purposes.
        ghosted_cannot_anything: %{
          id: "0H0STEDCANTSEE0RD0ANYTH1NG",
          name: l("People I ghosted cannot see me"),
          stereotype: true
        },
        silenced_cannot_reach_me: %{
          id: "1S11ENCEDTHEMS0CAN0TP1NGME",
          name: l("People I silenced aren't discoverable by me"),
          stereotype: true
        },
        cannot_discover_if_silenced: %{
          id: "2HEYS11ENCEDMES0CAN0TSEEME",
          name: l("People who silenced me cannot discover me"),
          stereotype: true
        }
      ],
      ### Grants are the entries of an ACL and define the permissions a user or circle has for content using this ACL.
      ###
      ### Data structure:
      ### * The outer keys are ACL names declared above.
      ### * The inner keys are circles declared above.
      ### * The inner values declare the verbs the user is permitted to see. Either a map of verb to boolean or a list
      ###   (where values are assumed to be true).
      grants: [
        ### Public ACLs need their permissions filled out
        # admins can care for every aspect of the instance
        instance_care: %{
          admin: :administer,
          mod: :moderate,
          local: :contribute,
          activity_pub: :interact,
          guest: :read
        },
        mods_may_manage: %{
          mod: role_verbs_moderate,
          admin: all_verb_names
        },
        everyone_may_see: %{
          guest: [:see],
          local: [:see],
          activity_pub: [:see]
        },
        everyone_may_read: %{
          guest: [:read],
          local: [:read],
          activity_pub: [:read]
        },
        everyone_may_see_read: %{
          guest: [:see, :read],
          local: [:see, :read],
          activity_pub: [:see, :read]
        },
        guests_may_see: %{guest: [:see] ++ verbs_basics},
        guests_may_read: %{guest: [:read] ++ verbs_basics},
        guests_may_see_read: %{guest: :read},
        # interact but NOT reply/message/mention
        remotes_may_interact: %{activity_pub: :interact},
        # interact and reply/message/mention
        remotes_may_participate: %{activity_pub: :participate},
        locals_may_read_interact: %{local: [:read, :follow] ++ verbs_react_quiet},
        # read + quiet-react + reply/mention/message, but NOT boost — for readable-but-
        # low-reach tiers (unlisted/quiet): locals can hold a conversation without the
        # content being amplified. `locals_may_read_interact` + `verbs_ping`.
        locals_may_read_reply: %{
          local: [:read, :follow] ++ verbs_react_quiet ++ verbs_ping
        },
        # the same tier for remote actors. Spelled as an explicit verb list rather than the `participate` ROLE for the same reason as its local twin: `role_verbs_participate` includes `verbs_sharing`, and boost is exactly what this tier withholds.
        remotes_may_read_reply: %{
          activity_pub: [:read, :follow] ++ verbs_react_quiet ++ verbs_ping
        },
        # interact but NOT reply/message/mention
        locals_may_interact: %{local: :interact},
        # interact and reply/message/mention
        locals_may_reply: %{local: :participate},
        # join + interact + contribute
        locals_may_contribute: %{local: :contribute},
        remotes_may_contribute: %{activity_pub: :contribute},
        locals_may_see: %{local: [:see]},
        locals_may_follow: %{local: [:follow]},
        # `:follow` is granted positively rather than inherited from a role, so an account that reviews follows simply does not carry this, instead of carrying `no_follow` to take it back. Guests are excluded: following needs an identity.
        everyone_may_follow: %{local: [:follow], activity_pub: [:follow]},
        locals_may_join: %{local: [:join, :follow]},
        # the positive grant that `open` membership is made of. `:join` is granted only here and by `locals_may_join`, so absence of both IS denial and no `no_join` negative is needed.
        everyone_may_join: %{guest: [:join], local: [:join], activity_pub: [:join]},
        everyone_may_request: %{local: [:request], activity_pub: [:request]},
        # The `*_interact` ACLs include `:follow` (the `verbs_interaction` set) on top of the reaction verbs (`verbs_react`). 
        everyone_may_see_interact: %{
          guest: [:see],
          local: [:see, :follow] ++ verbs_react,
          activity_pub: [:see, :follow] ++ verbs_react
        },
        locals_may_see_interact: %{
          local: [:see, :follow] ++ verbs_react
        },
        everyone_may_see_read_interact: %{
          guest: [:see, :read],
          local: [:see, :read, :follow] ++ verbs_react,
          activity_pub: [:see, :read, :follow] ++ verbs_react
        },
        locals_may_see_read_interact: %{
          local: [:see, :read, :follow] ++ verbs_react
        },
        everyone_may_read_interact: %{
          guest: [:read],
          local: [:read, :follow] ++ verbs_react_quiet,
          activity_pub: [:read, :follow] ++ verbs_react_quiet
        },
        # negative grants:
        ghosted_cannot_anything: %{ghost_them: verbs_negative.(all_verb_names)},
        silenced_cannot_reach_me: %{
          silence_them: verbs_negative.([:request, :mention, :message])
        },
        cannot_discover_if_silenced: %{silence_me: verbs_negative.([:see])},
        no_follow: %{local: verbs_negative.([:follow]), activity_pub: verbs_negative.([:follow])}
        # |> IO.inspect(label: "no_follow")
      ]

    # end of global boundaries

    bare_negative_grants = [
      # instance-wide negative permissions
      :ghosted_cannot_anything,
      :silenced_cannot_reach_me,
      :cannot_discover_if_silenced,
      # per-user negative permissions
      :my_cannot_discover_if_silenced
    ]

    negative_grants =
      bare_negative_grants ++
        [
          # per-user negative permissions
          :my_ghosted_cannot_anything,
          :my_silenced_cannot_reach_me
        ]

    ### Creating a user also entails inserting a default boundaries configuration for them.
    ###
    ### Notice that the predefined circles and ACLs here correspond to (some of) the stereotypes we declared above. The
    ### system uses this stereotype information to identify these special circles/ACLs in the database.
    config :bonfire,
      user_default_boundaries: %{
        circles: %{
          # users who have followed you
          followers: %{stereotype: :followers},
          # users who you have followed
          followed: %{stereotype: :followed},
          # users/instances you have ghosted
          ghost_them: %{stereotype: :ghost_them},
          # users/instances you have silenced
          silence_them: %{stereotype: :silence_them},
          # users who have silenced you
          silence_me: %{stereotype: :silence_me},
          # instances/actors I allow to federate with me (archipelago mode)
          allow_them: %{stereotype: :allow_them}
        },
        acls: %{
          ## ACLs that confer my personal permissions on things i have created
          # i_may_read:           %{stereotype: :i_may_read},
          # i_may_reply:          %{stereotype: :i_may_interact},
          i_may_administer: %{stereotype: :i_may_administer},
          my_followed_may_reply: %{stereotype: :followed_may_reply},
          ## "Negative" ACLs that apply overrides for ghosting and silencing purposes.
          my_ghosted_cannot_anything: %{stereotype: :ghosted_cannot_anything},
          my_silenced_cannot_reach_me: %{stereotype: :silenced_cannot_reach_me},
          my_cannot_discover_if_silenced: %{stereotype: :cannot_discover_if_silenced}
        },
        ### Data structure:
        ### * The outer keys are ACL names declared above.
        ### * The inner keys are circles declared above.
        ### * The inner values declare the verbs the user is permitted to see. Either a map of verb to boolean or a list
        ###   (where values are assumed to be true).
        ### * The special key `SELF` means the creating user.
        grants: %{
          ## ACLs that confer my personal permissions on things i have created
          # i_may_read:           %{SELF:  [:read, :see]},# not currently used
          # i_may_reply:          %{SELF:  [:read, :see, :create, :mention, :tag, :boost, :flag, :like, :follow, :reply]}, # not currently used
          i_may_administer: %{SELF: all_verb_names},
          ## "Negative" ACLs that apply overrides for ghosting and silencing purposes.
          # People/instances I ghost can't see (or interact with or anything) me or my objects
          my_ghosted_cannot_anything: %{ghost_them: verbs_negative.(all_verb_names)},
          # People/instances I silence can't ping me
          my_silenced_cannot_reach_me: %{
            silence_them: verbs_negative.([:request, :mention, :message])
          },
          # People who silence me can't see me or my objects in feeds and such (but can still read them if they have a direct link or come across my objects in a thread structure or such). This is an automatated invisible circle (i.e. I can't see who silenced me).
          my_cannot_discover_if_silenced: %{silence_me: verbs_negative.([:see])},
          my_followed_may_reply: %{followed: role_verbs_participate}
        },
        ### This lets us control access to the user themselves (e.g. to view their profile or mention them)
        controlleds: %{
          SELF:
            [
              # positive permissions
              :locals_may_reply,
              :remotes_may_participate,
              :i_may_administer
              # note that extra ACLs are added by `Bonfire.Boundaries.Scaffold.Users.default_visibility/0`
            ] ++ negative_grants
        }
      },
      # A Category (group or topic) is an actor with a character of its own, so it can be silenced like anyone else. Silencing keeps a reverse index on the object BEING silenced, so the category needs its own `silence_me` circle, its own negative ACL, and the grant joining the two. Users get all this at signup; a category gets it the first time somebody silences it, since most are never blocked by anyone and scaffolding it up front is rows on every group and topic ever created.
      #
      # Deliberately only what blocking needs. `ghost_them` and `silence_them` are the BLOCKER's own lists and the blocker is a user; a category ghosting somebody would be group moderation, which is a different feature.
      # Keyed by stereotype so each one carries its own complete wiring (circle, ACL, grant, and the ACL attached to the actor itself) and can be created alone. A given block only ever uses one of them, so only that one gets rows.
      # TODO: use these for users too, to keep DRY but also so they're each created on-demand and don't bloat the DB.
      block_boundaries_by_stereotype: %{
        # somebody silenced this category: the reverse index lives on the thing being silenced
        silence_me: %{
          circles: %{silence_me: %{stereotype: :silence_me}},
          acls: %{my_cannot_discover_if_silenced: %{stereotype: :cannot_discover_if_silenced}},
          grants: %{my_cannot_discover_if_silenced: %{silence_me: verbs_negative.([:see])}},
          controlleds: %{SELF: [:my_cannot_discover_if_silenced]}
        },
        # this category ghosted somebody, which is what a member ban is
        ghost_them: %{
          circles: %{ghost_them: %{stereotype: :ghost_them}},
          acls: %{my_ghosted_cannot_anything: %{stereotype: :ghosted_cannot_anything}},
          grants: %{my_ghosted_cannot_anything: %{ghost_them: verbs_negative.(all_verb_names)}},
          controlleds: %{SELF: [:my_ghosted_cannot_anything]}
        },
        # this category silenced somebody, the softer moderation act
        silence_them: %{
          circles: %{silence_them: %{stereotype: :silence_them}},
          acls: %{my_silenced_cannot_reach_me: %{stereotype: :silenced_cannot_reach_me}},
          grants: %{
            my_silenced_cannot_reach_me: %{
              silence_them: verbs_negative.([:request, :mention, :message])
            }
          },
          controlleds: %{SELF: [:my_silenced_cannot_reach_me]}
        }
      },
      remote_user_boundaries: %{
        circles: %{
          # users who have followed you
          followers: %{stereotype: :followers},
          # users who you have followed
          followed: %{stereotype: :followed},
          # users/instances you have ghosted
          ghost_them: %{stereotype: :ghost_them},
          # users/instances you have silenced
          silence_them: %{stereotype: :silence_them},
          # users who have silenced you
          silence_me: %{stereotype: :silence_me},
          # instances/actors I allow to federate with me (archipelago mode)
          allow_them: %{stereotype: :allow_them}
        },
        acls: %{
          ## ACLs that confer my personal permissions on things i have created
          i_may_administer: %{stereotype: :i_may_administer},
          ## "Negative" ACLs that apply overrides for ghosting and silencing purposes.
          my_cannot_discover_if_silenced: %{stereotype: :cannot_discover_if_silenced}
        },
        ### Data structure:
        ### * The outer keys are ACL names declared above.
        ### * The inner keys are circles declared above.
        ### * The inner values declare the verbs the user is permitted to see. Either a map of verb to boolean or a list
        ###   (where values are assumed to be true).
        ### * The special key `SELF` means the creating user.
        grants: %{
          ## ACLs that confer my personal permissions on things i have created
          # i_may_read:           %{SELF:  [:read, :see]},# not currently used
          # i_may_reply:          %{SELF:  [:read, :see, :create, :mention, :tag, :boost, :flag, :like, :follow, :reply]}, # not currently used
          i_may_administer: %{SELF: all_verb_names},
          ## "Negative" ACLs that apply overrides for ghosting and silencing purposes.
          # People who silence me can't see me or my objects in feeds and such (but can still read them if they have a direct link or come across my objects in a thread structure or such). This is an automatated invisible circle (i.e. I can't see who silenced me).
          my_cannot_discover_if_silenced: %{
            silence_me: verbs_negative.([:see]),
            silence_my_instance: verbs_negative.([:see])
          }
          # my_cannot_discover_if_silenced_instance: %{silence_my_instance: verbs_negative.([:see])}
        },
        ### This lets us control access to the user themselves (e.g. to view their profile or mention them)
        controlleds: %{
          SELF:
            [
              # positive permissions
              :locals_may_reply,
              :i_may_administer
              # note that extra ACLs are added by `Bonfire.Boundaries.Scaffold.Users.default_visibility/0`
            ] ++ bare_negative_grants
        }
      }

    ### Finally, we have a list of default acls to apply to newly created objects, which makes it possible for the user to administer their own stuff and enables ghosting and silencing to work.
    config :bonfire,
      object_default_boundaries: %{
        # negative
        acls:
          [
            # positive permissions
            :i_may_administer
          ] ++ negative_grants
      }

    config :bonfire, :ui,
      profile: [
        my_network: [
          "/boundaries/circles": l("Circles"),
          "/boundaries/ghosted": l("Ghosted"),
          "/boundaries/silenced": l("Silenced")
        ]
      ]

    # Metadata (label, icon, description) for named boundary presets, and dimensional
    # group boundary options. Used by Bonfire.Boundaries.Presets.
    # Instance admins can override or extend in runtime.exs.
    config :bonfire_boundaries,
      preset_order: ["public", "local", "mentions"],
      preset_dimensions: %{
        membership: %{
          label: l("Who can join?"),
          slug_order: [
            "open",
            "local:members",
            # see the archipelago note in :preset_acls above
            # "archipelago:members",
            "on_request",
            "invite_only"
          ],
          # `join_mode:` is what each slug MEANS for joining, and it is a public contract: the
          # Mastodon-compatible groups API returns it verbatim and derives `Account.locked` from it
          # (`"free" | "request" | "invite"`, see MASTO_GROUPS_API.md). Declared per slug here so a
          # new membership gets its behaviour from the one place that defines the slug, rather than
          # from a hand-maintained list somewhere else.
          options: %{
            "open" => %{
              label: l("Anyone"),
              icon: "fluent:globe-person-20-regular",
              description: l("Anyone (including remote users) can join freely"),
              join_mode: "free",
              disabled: l("Coming soon: requires groups federation")
            },
            "local:members" => %{
              label: l("Local members"),
              icon: "ph:campfire-duotone",
              description: l("Anyone on this instance can join freely"),
              join_mode: "free"
            },
            # see the archipelago note in :preset_acls above
            # "archipelago:members" => %{
            #   label: l("Archipelago members"),
            #   icon: "ph:planet-duotone",
            #   description: l("Anyone on a trusted linked instance can join freely"),
            #   join_mode: "free",
            #   disabled: l("Coming soon: requires archipelago feature")
            # },
            "on_request" => %{
              label: l("On request"),
              icon: "ph:hand-waving-duotone",
              description: l("Anyone can request to join; a moderator approves"),
              join_mode: "request"
            },
            "invite_only" => %{
              label: l("Invite only"),
              icon: "ph:lock-duotone",
              description: l("Only moderators can add members"),
              join_mode: "invite"
            }
          }
        },
        visibility: %{
          label: l("Who can see the group?"),
          slug_order: [
            "global",
            "nonfederated",
            "nonfederated:preview",
            "nonfederated:unlisted",
            "preview",
            "unlisted",
            # see the archipelago note in :preset_acls above
            # "archipelago",
            "local",
            "local:preview",
            "local:unlisted",
            "members:private"
          ],
          options: %{
            "global" => %{
              label: l("Public (federated)"),
              icon: "ph:globe-duotone",
              description: l("Anyone (including guests) can see and read the group; federated"),
              role: :interact,
              disabled: l("Coming soon: requires groups federation")
            },
            "nonfederated" => %{
              label: l("Public"),
              icon: "ph:house-duotone",
              description:
                l(
                  "Anyone (including guests) can see and read the group on this instance; not federated"
                ),
              role: :interact
            },
            "nonfederated:preview" => %{
              label: l("Discoverable · Members-only content"),
              icon: "fluent:globe-search-24-regular",
              description:
                l(
                  "Anyone on this instance can see the group exists, but only members can read content; not federated"
                ),
              role: :preview_discover
            },
            "nonfederated:unlisted" => %{
              label: l("Public, unlisted"),
              icon: "ph:link-simple-duotone",
              description:
                l(
                  "Anyone on this instance can read with a direct link; not listed; not federated"
                ),
              role: :unlisted_read
            },
            # see the archipelago note in :preset_acls above
            # "archipelago" => %{
            #   label: l("Archipelago"),
            #   icon: "ph:planet-duotone",
            #   description: l("Anyone on a trusted linked instance can see and read"),
            #   role: :interact,
            #   disabled: l("Coming soon: requires archipelago feature")
            # },
            "local" => %{
              label: l("Local"),
              icon: "ph:campfire-duotone",
              description: l("Anyone on this instance can see and read the group"),
              role: :interact
            },
            "preview" => %{
              label: l("Discoverable"),
              icon: "fluent:globe-search-24-regular",
              description:
                l("Anyone can see the group exists, but only members can read content"),
              role: :preview_discover,
              disabled: l("Coming soon: requires groups federation")
            },
            "local:preview" => %{
              label: l("Locally discoverable"),
              icon: "ph:eye-duotone",
              description:
                l("Local users can see the group exists, but only members can read content"),
              role: :preview_discover
            },
            "unlisted" => %{
              label: l("Unlisted"),
              icon: "ph:link-simple-duotone",
              description: l("Readable with a direct link, not shown in listings"),
              role: :unlisted_read,
              disabled: l("Coming soon: requires groups federation")
            },
            "local:unlisted" => %{
              label: l("Locally unlisted"),
              icon: "ph:link-simple-duotone",
              description: l("Local users can read with a direct link; not listed"),
              role: :unlisted_read
            },
            "members:private" => %{
              label: l("Members only"),
              icon: "ph:lock-duotone",
              description: l("Only members can see or read the group"),
              role: :interact
            }
          }
        },
        participation: %{
          label: l("Who can post and interact?"),
          slug_order: [
            "anyone",
            # see the archipelago note in :preset_acls above
            # "archipelago:contributors",
            "local:contributors",
            "group_members",
            "moderators"
          ],
          options: %{
            "anyone" => %{
              label: l("Anyone"),
              icon: "ph:globe-duotone",
              description: l("Anyone (including remote users) can post and interact"),
              disabled: l("Coming soon: requires groups federation")
            },
            # see the archipelago note in :preset_acls above
            # "archipelago:contributors" => %{
            #   label: l("Archipelago contributors"),
            #   icon: "ph:planet-duotone",
            #   description: l("Users on trusted linked instances can post and interact"),
            #   disabled: l("Coming soon: requires archipelago feature")
            # },
            "local:contributors" => %{
              label: l("Local contributors"),
              icon: "ph:campfire-duotone",
              description: l("Any local user can post and interact")
            },
            "group_members" => %{
              label: l("Members only"),
              icon: "ph:users-three-duotone",
              description: l("Only group members can post and interact")
            },
            "moderators" => %{
              label: l("Group moderators only"),
              icon: "ph:shield-duotone",
              description: l("Only group moderators can post; members can read and react")
            }
          }
        },
        default_content_visibility: %{
          label: l("How visible are posts by default?"),
          description:
            l(
              "Pre-fills the boundary selector when posting in the group. Authors can still change it. Affects future posts only."
            ),
          slug_order: [
            "public",
            "nonfederated",
            # see the archipelago note in :preset_acls above
            # "archipelago",
            "local",
            "public:preview",
            "nonfederated:preview",
            "local:preview",
            "unlisted",
            "nonfederated:unlisted",
            "local:unlisted",
            "members:private"
          ],
          options: %{
            "public" => %{
              label: l("Public (federated)"),
              icon: "ph:globe-duotone",
              description:
                l("Posts visible to anyone including guests and remote users; federated"),
              role: :interact,
              disabled: l("Coming soon: requires groups federation")
            },
            "nonfederated" => %{
              label: l("Public"),
              icon: "ph:house-duotone",
              description:
                l("Posts visible to anyone on this instance including guests; not federated"),
              role: :interact
            },
            "nonfederated:preview" => %{
              label: l("Preview (public)"),
              icon: "ph:eye-duotone",
              description:
                l("Post appears in feeds but full content is members-only; not federated"),
              role: :preview_discover
            },
            "nonfederated:unlisted" => %{
              label: l("Unlisted (public)"),
              icon: "ph:link-simple-duotone",
              description:
                l("Readable via direct link on this instance, not in feeds, no boosting"),
              role: :unlisted_read
            },
            # see the archipelago note in :preset_acls above
            # "archipelago" => %{
            #   label: l("Archipelago"),
            #   icon: "ph:planet-duotone",
            #   description: l("Posts visible to trusted linked instances"),
            #   role: :interact,
            #   disabled: l("Coming soon: requires archipelago feature")
            # },
            "local" => %{
              label: l("Local"),
              icon: "ph:campfire-duotone",
              description: l("Posts visible to logged-in users on this instance"),
              role: :interact
            },
            "public:preview" => %{
              label: l("Preview (public)"),
              icon: "ph:eye-duotone",
              description: l("Post appears in public feeds but full content is members-only"),
              role: :preview_discover,
              disabled: l("Coming soon: requires groups federation")
            },
            "local:preview" => %{
              label: l("Preview (local)"),
              icon: "ph:eye-duotone",
              description: l("Post appears in local feeds but full content is members-only"),
              role: :preview_discover
            },
            "unlisted" => %{
              label: l("Unlisted (public)"),
              icon: "ph:link-simple-duotone",
              description: l("Readable via direct link, not in feeds, no boosting"),
              role: :unlisted_read,
              disabled: l("Coming soon: requires groups federation")
            },
            "local:unlisted" => %{
              label: l("Unlisted (local)"),
              icon: "ph:link-simple-duotone",
              description:
                l("Readable via direct link for local users, not in feeds, no boosting"),
              role: :unlisted_read
            },
            "members:private" => %{
              label: l("Members only"),
              icon: "ph:lock-duotone",
              description: l("Posts only visible to group members"),
              role: :interact
            }
          }
        }
      },
      presets: %{
        "public" => %{
          label: l("Public"),
          icon: "ph:globe-duotone",
          description: l("Visible to everyone."),
          tooltip:
            l(
              "Public: visible to everyone. People on the fediverse can see, interact, and reply."
            )
        },
        "local" => %{
          label: l("Local"),
          icon: "ph:campfire-duotone",
          description: l("Everyone on this instance."),
          tooltip: l("Local: everyone on this instance can see, interact, and reply.")
        },
        # the same slug the visibility and content-default dimensions use, so a post and a group mean the same thing by it. `disabled:` until the composer offers it, the way `global` and `preview` are carried here before their features land.
        # ⚠️ the SLUG says unlisted (it matches Mastodon's API value, which is what code matches on) but the COPY must not: this federates as `cc: Public`, so receiving servers do list it, in remote followers' home timelines and on the author's profile. Naming the three places it skips is claimable; "unlisted" or "only people with the link" is not. See the unlisted plan doc.
        "unlisted" => %{
          label: l("Quiet public"),
          icon: "ph:link-simple-duotone",
          description: l("Public, but not promoted."),
          tooltip:
            l(
              "Quiet public: anyone can read it, and it may reach your followers, but it stays out of discovery feeds and search."
            ),
          disabled: l("Coming soon")
        },
        "mentions" => %{
          label: l("Mentions"),
          icon: "ph:at-duotone",
          description: l("Only people you @mention."),
          tooltip: l("Mentions: anyone mentioned will be able to see, interact, and reply.")
        },
        "follows" => %{
          label: l("Follows"),
          icon: "ph:eye-duotone",
          description: l("Only people you follow."),
          tooltip: l("Follows: people who I follow may read, like, boost and reply.")
        },
        "private" => %{
          label: l("Private"),
          icon: "ph:eye-slash-duotone",
          description: l("Only you."),
          tooltip: l("Private: only visible to the creator and/or caretaker.")
        }
      }
  end
end
