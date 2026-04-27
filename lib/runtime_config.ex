defmodule Bonfire.Boundaries.RuntimeConfig do
  @behaviour Bonfire.Common.ConfigModule
  def config_module, do: true

  use Bonfire.Common.Localise

  @doc """
  NOTE: you can override this default config in your app's runtime.exs, by placing similarly-named config keys below the `Bonfire.Common.Config.LoadExtensionsConfig.load_configs` line
  """
  def config do
    import Config

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
        :tag,
        :label,
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
    verbs_see_request = [:see, :request]
    verbs_read_request = [:read, :request]
    verbs_see_read_request = [:read, :see, :request] ++ verbs_basics
    verbs_interaction = [:follow]
    verbs_liking = [:like]
    verbs_sharing = [:boost]
    verbs_ping = [:reply, :mention, :message]
    verbs_critique = [:quote]
    verbs_curate = [:tag, :describe, :annotate, :pin]
    verbs_contrib = [:create, :tag, :describe, :annotate]
    verbs_edit = [:edit, :tag, :describe, :annotate]
    verbs_mod = [:invite, :label, :mediate, :block, :delete]

    # verbs_interact_minus_follow =
    #   verbs_see_read_request ++ [:like]

    verbs_interact_minus_boost = verbs_see_read_request ++ verbs_interaction ++ verbs_liking
    verbs_interact_minus_like = verbs_see_read_request ++ verbs_interaction ++ verbs_sharing

    # like + bookmark + flag — quiet reactions that don't amplify reach (safe for unlisted/quiet content)
    verbs_react_quiet = verbs_liking ++ [:bookmark, :flag]

    # like + boost + bookmark + flag — full reactions including amplification (for discoverable/preview content)
    verbs_react = verbs_react_quiet ++ verbs_sharing

    role_verbs_interact =
      verbs_see_read_request ++ verbs_interaction ++ verbs_liking ++ verbs_sharing

    # verbs_participate_message_minus_follow =
    #   verbs_interact_minus_follow ++ verbs_ping

    verbs_participate_minus_boost = verbs_interact_minus_boost ++ verbs_ping

    role_verbs_participate = role_verbs_interact ++ verbs_ping ++ [:join]

    role_verbs_critique = role_verbs_participate ++ verbs_critique

    role_verbs_curate = role_verbs_critique ++ verbs_curate

    role_verbs_editor = role_verbs_curate ++ verbs_contrib

    role_verbs_contribute = role_verbs_curate ++ verbs_contrib

    role_verbs_editor_and_contribute = role_verbs_editor ++ verbs_contrib

    # verbs_join_and_contribute = role_verbs_contribute ++ [:invite]

    role_verbs_moderate = role_verbs_contribute ++ verbs_mod

    # preset ACLs to show when editing boundaries
    basic_acls = [
      :everyone_may_see_read,
      :remotes_may_interact,
      :remotes_may_reply,
      :locals_may_interact,
      :locals_may_reply
    ]

    config :bonfire,
      verbs: verbs,
      preferred_verb_order: all_verb_names,
      default_verbs_for: default_verbs_for,
      role_verbs: %{
        none: %{read_only: true},
        read: %{can_verbs: verbs_see_read_request, read_only: true},
        react: %{can_verbs: verbs_interact_minus_boost, read_only: true},
        share: %{can_verbs: verbs_interact_minus_like, read_only: true},
        interact: %{
          can_verbs: role_verbs_interact,
          read_only: true,
          label: l("Fully visible"),
          description: l("Can see, read, and interact with content"),
          icon: "ph:eye-duotone"
        },
        # see + react (no read) — for discoverable visibility
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
        participate: %{can_verbs: role_verbs_participate, read_only: true},
        critique: %{can_verbs: role_verbs_critique, read_only: true},
        curate: %{can_verbs: role_verbs_curate, read_only: true},
        edit: %{can_verbs: role_verbs_editor, read_only: true},
        contribute: %{usage: :ops, can_verbs: role_verbs_contribute, read_only: true},
        moderate: %{usage: :ops, can_verbs: role_verbs_moderate, read_only: false},
        administer: %{can_verbs: all_verb_names, read_only: true},
        cannot_anything: %{cannot_verbs: all_verb_names, read_only: true},
        cannot_request: %{cannot_verbs: [:request], read_only: true},
        cannot_discover: %{
          cannot_verbs: Enum.reject(all_verb_names, fn v -> v in verbs_read_request end),
          read_only: true
        },
        cannot_read: %{
          cannot_verbs: Enum.reject(all_verb_names, fn v -> v == :request end),
          read_only: true
        },
        cannot_react: %{
          cannot_verbs: Enum.reject(all_verb_names, fn v -> v in verbs_interact_minus_like end),
          read_only: true
        },
        cannot_share: %{
          cannot_verbs: Enum.reject(all_verb_names, fn v -> v in verbs_interact_minus_boost end),
          read_only: true
        },
        cannot_interact: %{
          cannot_verbs: Enum.reject(all_verb_names, fn v -> v in verbs_see_read_request end),
          read_only: true
        },
        cannot_participate: %{
          cannot_verbs: Enum.reject(all_verb_names, fn v -> v in role_verbs_interact end),
          read_only: true
        },
        cannot_critique: %{
          cannot_verbs: Enum.reject(all_verb_names, fn v -> v in role_verbs_participate end),
          read_only: true
        },
        cannot_curate: %{
          cannot_verbs: Enum.reject(all_verb_names, fn v -> v in role_verbs_critique end),
          read_only: true
        },
        cannot_contribute: %{
          usage: :ops,
          cannot_verbs: Enum.reject(all_verb_names, fn v -> v in role_verbs_curate end),
          read_only: true
        },
        cannot_administer: %{
          cannot_verbs:
            Enum.reject(all_verb_names, fn v -> v in role_verbs_editor_and_contribute end),
          read_only: true
        }
      },
      role_to_grant: [
        default: :participate
      ],
      verbs_to_grant: [
        default: role_verbs_participate,
        message: verbs_participate_minus_boost
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
            :locals_may_read_interact
          ],
      #  used for setting boundaries
      preset_acls: %{
        "public" => [
          :everyone_may_see_read,
          :locals_may_reply,
          :remotes_may_reply
        ],
        "unlisted" => [
          :everyone_may_see_read
        ],
        "local" => [:locals_may_reply],
        "private" => [],

        # --- Membership presets ---
        "open" => [:everyone_may_see_read, :locals_may_contribute, :remotes_may_contribute],
        "local:members" => [:locals_may_join],
        "on_request" => [:everyone_may_request],
        # "invite_only": no grants, members circle controls — no new entry needed?

        # "open": reuses existing "open" preset (ACL grants work; AP remote join UI shown as coming soon)
        "archipelago:members" => [],

        # --- Participation presets  ---
        "anyone" => [:locals_may_contribute, :remotes_may_contribute],
        "archipelago:contributors" => [],
        "local:contributors" => [:locals_may_contribute],
        # "group_members": no grants, members circle controls

        # --- Group visibility presets  ---
        # "visible" retired — groups use dimensional presets (membership/visibility/participation)
        # full (see+read+interact): global/archipelago disabled until groups federation is complete
        "global" => [:everyone_may_see_read_interact],
        "archipelago" => [],
        # "local" => reuses existing general "local" preset
        # nonfederated — guests+locals can read on-instance; NOT federated (explicit deny to :activity_pub applied in Classify.Boundaries)
        "nonfederated" => [:guests_may_see_read, :locals_may_see_read_interact],
        "nonfederated:discoverable" => [:guests_may_see, :locals_may_see_interact],
        "nonfederated:unlisted" => [:guests_may_read, :locals_may_read_interact],
        "members:private" => [],
        # unlisted (readable with direct link, NOT indexed/listed — no :see, no boost)
        # global/archipelago unlisted disabled until groups federation is complete
        "unlisted" => [:everyone_may_read_interact],
        "archipelago:unlisted" => [],
        "local:unlisted" => [:locals_may_read_interact],
        # discoverable (see+react but NOT :read; :read granted to members circle in Classify.Boundaries)
        # global/archipelago discoverable disabled until groups federation is complete
        "discoverable" => [:everyone_may_see_interact],
        "archipelago:discoverable" => [],
        "local:discoverable" => [:locals_may_see_interact],

        # --- Default content visibility presets ---
        # full: "public"/"local" reuse existing general presets; "archipelago" no-op shared with group visibility above
        # members:private shared with visibility preset above
        # nonfederated DCV — public on-instance, not federated
        "nonfederated" => [:guests_may_see_read, :locals_may_see_read_interact],
        "nonfederated:quiet" => [:guests_may_read, :locals_may_read_interact],
        "nonfederated:preview" => [:guests_may_see, :locals_may_see_interact],
        "public:quiet" => [:everyone_may_read_interact],
        "archipelago:quiet" => [],
        "local:quiet" => [:locals_may_read_interact],
        # preview: public/archipelago disabled until groups federation is complete
        "public:preview" => [:everyone_may_see_interact],
        "archipelago:preview" => [],
        "local:preview" => [:locals_may_see_interact]
      },
      #  used for matching saved boundaries to presets:
      preset_acls_match: %{
        # TODO: better yet, generate this from the `preset_acls` list above.
        "public" => [
          :everyone_may_see,
          :everyone_may_read,
          :everyone_may_see_read,
          :remotes_may_interact,
          :remotes_may_reply
        ],
        "unlisted" => [:everyone_may_read_interact],
        "local" => [:locals_may_read_interact, :locals_may_interact, :locals_may_reply],
        "local:unlisted" => [:locals_may_read_interact],
        "local:discoverable" => [:locals_may_see_interact],
        "discoverable" => [:everyone_may_see_interact],
        "global" => [:everyone_may_see_read_interact],
        "nonfederated" => [:guests_may_see_read, :locals_may_see_read_interact],
        "nonfederated:discoverable" => [:guests_may_see, :locals_may_see_interact],
        "nonfederated:unlisted" => [:guests_may_read, :locals_may_read_interact],
        # Membership markers — must be unique to membership (no overlap with visibility),
        # so detection isn't fooled by a visibility ACL matching the wrong dimension.
        "open" => [:locals_may_contribute, :remotes_may_contribute],
        "local:members" => [:locals_may_join],
        "on_request" => [:everyone_may_request]
      }

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
        guests_may_see_read: %{
          id: "7W1DE1YAVA11AB1ET0SEENREAD",
          name: l("Publicly discoverable and readable")
        },
        guests_may_see: %{
          id: "50VCANF1NDMEBVTCAN0T0PENME",
          name: l("Publicly discoverable, but contents may be hidden")
        },
        guests_may_read: %{
          id: "50VCANREAD1FY0VHAVETHE11NK",
          name: l("Publicly readable, but not necessarily discoverable")
        },
        remotes_may_interact: %{
          id: "5REM0TEPE0P1E1NTERACTREACT",
          name: l("Remote actors may read and interact")
        },
        remotes_may_reply: %{
          id: "5REM0TEPE0P1E1NTERACTREP1Y",
          name: l("Remote actors may read, interact and reply")
        },
        remotes_may_contribute: %{
          id: "7REM0TEACT0RSCANC0NTR1BVTE",
          name: l("Remote actors may contribute")
        },
        locals_may_read_interact: %{
          id: "10CA1SMAYSEEANDREAD0N1YN0W",
          name: l("Visible to local users")
        },
        locals_may_interact: %{
          id: "710CA1SMY1NTERACTN0TREP1YY",
          name: l("Local users may read and interact")
        },
        locals_may_reply: %{
          id: "710CA1SMY1NTERACTANDREP1YY",
          name: l("Local users may read, interact and reply")
        },
        locals_may_contribute: %{
          id: "1ANY10CA1VSERCANC0NTR1BVTE",
          name: l("Local users may contribute")
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

        no_follow: %{
          id: "1MVSTREQVESTBEF0REF0110W1N",
          name: l("People must request to follow")
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
        guests_may_see: %{guest: verbs_see_request ++ verbs_basics},
        guests_may_read: %{guest: verbs_read_request ++ verbs_basics},
        guests_may_see_read: %{guest: :read},
        # interact but NOT reply/message/mention
        remotes_may_interact: %{activity_pub: :interact},
        # interact and reply/message/mention
        remotes_may_reply: %{activity_pub: :participate},
        locals_may_read_interact: %{local: [:read] ++ verbs_react_quiet},
        # interact but NOT reply/message/mention
        locals_may_interact: %{local: :interact},
        # interact and reply/message/mention
        locals_may_reply: %{local: :participate},
        # join + interact + contribute
        locals_may_contribute: %{local: :contribute},
        remotes_may_contribute: %{activity_pub: :contribute},
        locals_may_see: %{local: [:see]},
        locals_may_follow: %{local: [:follow]},
        locals_may_join: %{local: [:join, :follow]},
        everyone_may_request: %{local: [:request], activity_pub: [:request]},
        everyone_may_see_interact: %{
          guest: [:see],
          local: [:see] ++ verbs_react,
          activity_pub: [:see] ++ verbs_react
        },
        locals_may_see_interact: %{
          local: [:see] ++ verbs_react
        },
        everyone_may_see_read_interact: %{
          guest: [:see, :read],
          local: [:see, :read] ++ verbs_react,
          activity_pub: [:see, :read] ++ verbs_react
        },
        locals_may_see_read_interact: %{
          local: [:see, :read] ++ verbs_react
        },
        everyone_may_read_interact: %{
          guest: [:read],
          local: [:read] ++ verbs_react_quiet,
          activity_pub: [:read] ++ verbs_react_quiet
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
          silence_me: %{stereotype: :silence_me}
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
              :remotes_may_reply,
              :i_may_administer
              # note that extra ACLs are added by `Bonfire.Boundaries.Scaffold.Users.default_visibility/0`
            ] ++ negative_grants
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
          silence_me: %{stereotype: :silence_me}
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
            "archipelago:members",
            "on_request",
            "invite_only"
          ],
          options: %{
            "open" => %{
              label: l("Anyone"),
              icon: "fluent:globe-person-20-regular",
              description: l("Anyone (including remote users) can join freely"),
              disabled: l("Coming soon: requires groups federation")
            },
            "local:members" => %{
              label: l("Local members"),
              icon: "ph:campfire-duotone",
              description: l("Anyone on this instance can join freely")
            },
            "archipelago:members" => %{
              label: l("Archipelago members"),
              icon: "ph:planet-duotone",
              description: l("Anyone on a trusted linked instance can join freely"),
              disabled: l("Coming soon: requires archipelago feature")
            },
            "on_request" => %{
              label: l("On request"),
              icon: "ph:hand-waving-duotone",
              description: l("Anyone can request to join; a moderator approves")
            },
            "invite_only" => %{
              label: l("Invite only"),
              icon: "ph:lock-duotone",
              description: l("Only moderators can add members")
            }
          }
        },
        visibility: %{
          label: l("Who can see the group?"),
          slug_order: [
            "global",
            "nonfederated",
            "nonfederated:discoverable",
            "nonfederated:unlisted",
            "discoverable",
            "unlisted",
            "archipelago",
            "local",
            "local:discoverable",
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
            "nonfederated:discoverable" => %{
              label: l("Public, discoverable only"),
              icon: "fluent:globe-search-24-regular",
              description:
                l(
                  "Anyone on this instance can see the group exists, but only members can read content; not federated"
                ),
              role: :discover
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
            "archipelago" => %{
              label: l("Archipelago"),
              icon: "ph:planet-duotone",
              description: l("Anyone on a trusted linked instance can see and read"),
              role: :interact,
              disabled: l("Coming soon: requires archipelago feature")
            },
            "local" => %{
              label: l("Local"),
              icon: "ph:campfire-duotone",
              description: l("Anyone on this instance can see and read the group"),
              role: :interact
            },
            "discoverable" => %{
              label: l("Discoverable"),
              icon: "fluent:globe-search-24-regular",
              description:
                l("Anyone can see the group exists, but only members can read content"),
              role: :discover,
              disabled: l("Coming soon: requires groups federation")
            },
            "local:discoverable" => %{
              label: l("Locally discoverable"),
              icon: "ph:eye-duotone",
              description:
                l("Local users can see the group exists, but only members can read content"),
              role: :discover
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
            "archipelago:contributors",
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
            "archipelago:contributors" => %{
              label: l("Archipelago contributors"),
              icon: "ph:planet-duotone",
              description: l("Users on trusted linked instances can post and interact"),
              disabled: l("Coming soon: requires archipelago feature")
            },
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
            "archipelago",
            "local",
            "public:preview",
            "nonfederated:preview",
            "local:preview",
            "public:quiet",
            "nonfederated:quiet",
            "local:quiet",
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
              role: :discover
            },
            "nonfederated:quiet" => %{
              label: l("Quiet (public)"),
              icon: "ph:link-simple-duotone",
              description:
                l("Readable via direct link on this instance, not in feeds, no boosting"),
              role: :unlisted_read
            },
            "archipelago" => %{
              label: l("Archipelago"),
              icon: "ph:planet-duotone",
              description: l("Posts visible to trusted linked instances"),
              role: :interact,
              disabled: l("Coming soon: requires archipelago feature")
            },
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
              role: :discover,
              disabled: l("Coming soon: requires groups federation")
            },
            "local:preview" => %{
              label: l("Preview (local)"),
              icon: "ph:eye-duotone",
              description: l("Post appears in local feeds but full content is members-only"),
              role: :discover
            },
            "public:quiet" => %{
              label: l("Quiet (public)"),
              icon: "ph:link-simple-duotone",
              description: l("Readable via direct link, not in feeds, no boosting"),
              role: :unlisted_read,
              disabled: l("Coming soon: requires groups federation")
            },
            "local:quiet" => %{
              label: l("Quiet (local)"),
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
          icon: "heroicons-solid:eye-off",
          description: l("Only you."),
          tooltip: l("Private: only visible to the creator and/or caretaker.")
        }
      }
  end
end
