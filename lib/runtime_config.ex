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
        icon: "Heroicons-Solid:Eye",
        summary: l("Discoverable in lists (like feeds)")
      },
      read: %{
        id: "0EAD1NGSVTTER1YFVNDAMENTA1",
        verb: l("Read"),
        icon: "bxs:BookReader",
        summary: l("Readable/visible (if you can see or have a direct link)")
      },
      bookmark: %{
        id: "1B00KMARKMYGREATESTF1ND1NG",
        verb: l("Bookmark"),
        icon: "carbon:bookmark",
        summary: l("Bookmark an object (only visible to you)")
      },
      like: %{
        id: "11KES1ND1CATEAM11DAPPR0VA1",
        verb: l("Like"),
        icon: "bxs:Star",
        summary: l("Like an object (and notify the author)")
      },
      boost: %{
        id: "300ST0R0RANN0VCEANACT1V1TY",
        verb: l("Boost"),
        icon: "system-uicons:retweet",
        summary: l("Boost an object (and notify the author)")
      },
      flag: %{
        id: "71AGSPAM0RVNACCEPTAB1E1TEM",
        verb: l("Flag"),
        icon: "bxs:FlagAlt",
        summary:
          l(
            "Flag an object for a moderator to review (please note that anyone who can see or read something can flag it anyway)"
          )
      },
      reply: %{
        id: "71TCREAT1NGA11NKEDRESP0NSE",
        verb: l("Reply"),
        icon: "bx:Reply",
        summary: l("Reply to an activity or post")
      },
      annotate: %{
        id: "110VET0ANN0TATEEVERYTH1NGS",
        verb: l("Annotate"),
        icon: "heroicons-outline:pencil",
        summary: l("Annotate a video or other content")
      },
      mention: %{
        id: "0EFERENC1NGTH1NGSE1SEWHERE",
        verb: l("Mention"),
        icon: "bx:At",
        summary: l("Mention a user or object (and notify them)")
      },
      message: %{
        id: "40NTACTW1THAPR1VATEMESSAGE",
        verb: l("Message"),
        icon: "bxs:Send",
        summary: l("Send a message")
      },
      tag: %{
        id: "4ATEG0R1S1NGNGR0VP1NGSTVFF",
        verb: l("Tag"),
        icon: "bxs:PurchaseTag",
        summary: l("Tag a user or object, or publish in a topic")
      },
      label: %{
        id: "7PDATETHESTATVS0FS0METH1NG",
        verb: l("Label"),
        icon: "fluent:status-16-filled",
        summary: l("Set/update a status or label")
      },
      follow: %{
        id: "20SVBSCR1BET0THE0VTPVT0F1T",
        verb: l("Follow"),
        icon: "bx:Walk",
        summary: l("Follow a user or thread or whatever")
      },
      schedule: %{
        id: "7SCHEDV1EF1XEDDES1REDDATES",
        verb: l("Schedule"),
        icon: "akar-icons:schedule",
        summary: l("Set an expected or desired date")
      },
      pin: %{
        id: "1P1NN1NNG1S11KEH1GH11GHT1T",
        verb: l("Pin"),
        icon: "eos-icons:pin",
        summary: l("Pin something to highlight it")
      },
      create: %{
        id: "4REATE0RP0STBRANDNEW0BJECT",
        verb: l("Create"),
        icon: "bxs:Pen",
        summary: l("Create a post or other object")
      },
      edit: %{
        id: "4HANG1NGVA1VES0FPR0PERT1ES",
        verb: l("Edit"),
        icon: "bx:Highlight",
        summary: l("Modify the contents of an existing object")
      },
      delete: %{
        id: "4AKESTVFFG0AWAYPERMANENT1Y",
        verb: l("Delete"),
        icon: "bxs:TrashAlt",
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
        icon: "bx:ToggleRight",
        summary: l("Enable/disable extensions or features"),
        scope: :instance
      },
      describe: %{
        id: "1CANADD0M0D1FY1NF0METADATA",
        verb: l("Describe"),
        icon: "bx:CommentEdit",
        summary: l("Edit info and metadata, eg. thread titles"),
        scope: :instance
      },
      grant: %{
        id: "1T0ADDED1TREM0VEB0VNDAR1ES",
        verb: l("Grant"),
        icon: "bx:Key",
        summary: l("Add, edit or remove boundaries"),
        scope: :instance
      },
      assign: %{
        id: "1T0ADDC1RC1ES0RASS1GNR01ES",
        verb: l("Assign"),
        icon: "bxs:UserBadge",
        summary: l("Assign roles or tasks"),
        scope: :instance
      },
      invite: %{
        id: "11NV1TESPE0P1E0RGRANTENTRY",
        verb: l("Invite"),
        icon: "bx:Gift",
        summary: l("Join without invitation and invite others"),
        scope: :instance
      },
      mediate: %{
        id: "1T0SEEF1AGSANDMAKETHEPEACE",
        verb: l("Mediate"),
        icon: "bxs:FlagCheckered",
        summary: l("See flags"),
        scope: :instance
      },
      block: %{
        id: "1T0MANAGEB10CKGH0STS11ENCE",
        verb: l("Block"),
        icon: "bx:Block",
        summary: l("Manage blocks"),
        scope: :instance
      },
      configure: %{
        id: "1T0C0NF1GVREGENERA1SETT1NG",
        verb: l("Configure"),
        icon: "Heroicons-Solid:Adjustments",
        summary: l("Change general settings"),
        scope: :instance
      }
    ]

    all_verb_names = Enum.map(verbs, &elem(&1, 0))
    # |> IO.inspect()
    verbs_negative = fn verbs ->
      Enum.reduce(verbs, %{}, &Map.put(&2, &1, false))
    end

    verbs_see_request = [:see, :request]
    verbs_read_request = [:read, :request]
    verbs_see_read_request = [:read, :see, :request]
    verbs_interaction = [:like, :follow, :flag]
    verbs_sharing = [:boost, :pin]
    verbs_ping = [:reply, :mention, :message]
    verbs_contrib = [:create, :tag, :describe]
    verbs_edit = [:edit, :tag, :describe]
    verbs_mod = [:invite, :label, :mediate, :block, :delete]

    # verbs_interact_minus_follow =
    #   verbs_see_read_request ++ [:like]

    verbs_interact_minus_boost = verbs_see_read_request ++ verbs_interaction
    verbs_interact_incl_boost = verbs_interact_minus_boost ++ verbs_sharing

    # verbs_participate_message_minus_follow =
    #   verbs_interact_minus_follow ++ verbs_ping

    verbs_participate_message_minus_boost = verbs_interact_minus_boost ++ verbs_ping

    verbs_participate_and_message = verbs_interact_incl_boost ++ verbs_ping

    verbs_editor = verbs_participate_and_message ++ verbs_edit

    verbs_contribute = verbs_participate_and_message ++ verbs_contrib

    # verbs_join_and_contribute = verbs_contribute ++ [:invite]

    verbs_moderate = verbs_contribute ++ verbs_mod

    basic_acls = [
      :guests_may_see_read,
      :remotes_may_interact,
      :remotes_may_reply,
      :locals_may_interact,
      :locals_may_reply
    ]

    public_acls =
      basic_acls ++
        [
          :guests_may_see,
          :guests_may_read,
          :locals_may_read
        ]

    cannot_read = Enum.reject(all_verb_names, fn v -> v == :request end)
    cannot_discover = Enum.reject(all_verb_names, fn v -> v in verbs_read_request end)
    cannot_interact = Enum.reject(all_verb_names, fn v -> v in verbs_see_read_request end)
    cannot_participate = Enum.reject(all_verb_names, fn v -> v in verbs_interact_incl_boost end)

    cannot_contribute =
      Enum.reject(all_verb_names, fn v -> v in verbs_participate_and_message end)

    cannot_administer = Enum.reject(all_verb_names, fn v -> v in verbs_contribute end)

    config :bonfire,
      verbs: verbs,
      role_verbs: %{
        none: %{read_only: true},
        read: %{can_verbs: verbs_see_read_request, read_only: true},
        interact: %{can_verbs: verbs_interact_incl_boost, read_only: true},
        participate: %{can_verbs: verbs_participate_and_message, read_only: true},
        edit: %{can_verbs: verbs_editor, read_only: true},
        contribute: %{usage: :ops, can_verbs: verbs_contribute, read_only: true},
        moderate: %{usage: :ops, can_verbs: verbs_moderate, read_only: false},
        administer: %{can_verbs: all_verb_names, read_only: true},
        cannot_discover: %{cannot_verbs: cannot_discover, read_only: true},
        cannot_read: %{cannot_verbs: cannot_read, read_only: true},
        cannot_interact: %{cannot_verbs: cannot_interact, read_only: true},
        cannot_participate: %{cannot_verbs: cannot_participate, read_only: true},
        cannot_contribute: %{usage: :ops, cannot_verbs: cannot_contribute, read_only: true},
        cannot_administer: %{cannot_verbs: cannot_administer, read_only: true}
      },
      role_to_grant: [
        default: :participate
      ],
      verbs_to_grant: [
        default: verbs_participate_and_message,
        message: verbs_participate_message_minus_boost
      ],
      # preset ACLs to show when editing boundaries
      acls_for_dropdown: basic_acls,
      # what boundaries we can display to everyone when applied on objects
      public_acls_on_objects: public_acls,
      #  used for setting boundaries
      preset_acls: %{
        "public" => [
          :guests_may_see_read,
          :locals_may_reply,
          :remotes_may_reply
        ],
        "local" => [:locals_may_reply],
        "open" => [:guests_may_see_read, :locals_may_contribute, :remotes_may_contribute],
        "visible" => [
          :no_follow,
          :guests_may_see_read,
          :locals_may_interact,
          :remotes_may_interact
        ],
        "private" => []
      },
      #  used for matching saved boundaries to presets:
      preset_acls_match: %{
        "public" => [
          :guests_may_see,
          :guests_may_read,
          :guests_may_see_read,
          :remotes_may_interact,
          :remotes_may_reply
        ],
        "local" => [:locals_may_read, :locals_may_interact, :locals_may_reply],
        "open" => [:guests_may_see_read, :locals_may_contribute, :remotes_may_contribute],
        "visible" => [
          :no_follow,
          :locals_may_interact,
          :remotes_may_interact
        ]
      }

    # create_verbs: [
    #   # block:  Bonfire.Data.Social.Block,
    #   boost: Bonfire.Data.Social.Boost,
    #   follow: Bonfire.Data.Social.Follow,
    #   flag: Bonfire.Data.Social.Flag,
    #   like: Bonfire.Data.Social.Like
    # ],

    ### Now follows quite a lot of fixtures that must be inserted into the database.

    config :bonfire,
      ### Users are placed into one or more circles, either by users or by the system. Circles referenced in ACLs have the
      ### effect of applying to all users in those circles.
      circles: %{
        ### Public circles used to categorise broadly how much of a friend/do the user is.
        guest: %{id: "0AND0MSTRANGERS0FF1NTERNET", name: l("Guests")},
        local: %{id: "3SERSFR0MY0VR10CA11NSTANCE", name: l("Local Users")},
        activity_pub: %{
          id: "7EDERATEDW1THANACT1V1TYPVB",
          name: l("Remote ActivityPub Actors")
        },
        admin: %{id: "0ADM1NSVSERW1THSVPERP0WERS", name: l("Instance Admins")},
        mod: %{id: "10VE1YM0DSHE1PHEA1THYC0MMS", name: l("Instance Moderators")},

        ### Stereotypes - placeholders for special per-user circles the system will manage.
        followers: %{
          id: "7DAPE0P1E1PERM1TT0F0110WME",
          name: l("Those who follow me"),
          stereotype: true
        },
        followed: %{
          id: "4THEPE0P1ES1CH00SET0F0110W",
          name: l("Those I follow"),
          stereotype: true
        },
        ghost_them: %{
          id: "7N010NGERC0NSENTT0Y0VN0WTY",
          name: l("Those I ghosted"),
          stereotype: true
        },
        silence_them: %{
          id: "7N010NGERWANTT011STENT0Y0V",
          name: l("Those I silenced"),
          stereotype: true
        },
        silence_me: %{
          id: "0KF1NEY0VD0N0TWANTT0HEARME",
          name: l("Those who silenced me"),
          stereotype: true
        }
      },
      ### ACLs (Access Control Lists) are reusable lists of permissions assigned to users and circles. Objects in bonfire
      ### have one or more ACLs attached and we combine the results of all of them to determine whether a user is permitted
      ### to perform a particular operation.
      acls: %{
        instance_care: %{
          id: "01SETT1NGSF0R10CA11NSTANCE",
          name: l("Local instance roles & boundaries")
        },

        ### Public ACLs that allow basic control over visibility and interactions.
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
        locals_may_read: %{
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
      },
      ### Grants are the entries of an ACL and define the permissions a user or circle has for content using this ACL.
      ###
      ### Data structure:
      ### * The outer keys are ACL names declared above.
      ### * The inner keys are circles declared above.
      ### * The inner values declare the verbs the user is permitted to see. Either a map of verb to boolean or a list
      ###   (where values are assumed to be true).
      grants: %{
        ### Public ACLs need their permissions filled out
        # admins can care for every aspect of the instance
        instance_care: %{
          admin: :administer,
          mod: :moderate,
          local: :contribute,
          activity_pub: :interact,
          guest: :read
        },
        guests_may_see_read: %{guest: :read},
        guests_may_see: %{guest: verbs_see_request},
        guests_may_read: %{guest: verbs_read_request},
        # interact but NOT reply/message/mention
        remotes_may_interact: %{activity_pub: :interact},
        # interact and reply/message/mention
        remotes_may_reply: %{activity_pub: :participate},
        locals_may_read: %{local: :read},
        # interact but NOT reply/message/mention
        locals_may_interact: %{local: :interact},
        # interact and reply/message/mention
        locals_may_reply: %{local: :participate},
        # join + interact + contribute
        locals_may_contribute: %{local: :contribute},
        remotes_may_contribute: %{activity_pub: :contribute},
        # negative grants:
        ghosted_cannot_anything: %{ghost_them: verbs_negative.(all_verb_names)},
        silenced_cannot_reach_me: %{
          silence_them: verbs_negative.([:mention, :message, :reply])
        },
        cannot_discover_if_silenced: %{silence_me: verbs_negative.([:see])},
        no_follow: %{local: verbs_negative.([:follow]), activity_pub: verbs_negative.([:follow])}
        # |> IO.inspect(label: "no_follow")
      }

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
            silence_them: verbs_negative.([:mention, :message])
          },
          # People who silence me can't see me or my objects in feeds and such (but can still read them if they have a direct link or come across my objects in a thread structure or such). This is an automatated invisible circle (i.e. I can't see who silenced me).
          my_cannot_discover_if_silenced: %{silence_me: verbs_negative.([:see])},
          my_followed_may_reply: %{followed: verbs_participate_and_message}
        },
        ### This lets us control access to the user themselves (e.g. to view their profile or mention them)
        controlleds: %{
          SELF:
            [
              # positive permissions
              :locals_may_reply,
              :remotes_may_reply,
              :i_may_administer
              # note that extra ACLs are added by `Bonfire.Boundaries.Users.default_visibility/0`
            ] ++ negative_grants
        }
      },
      remote_user_boundaries: %{
        circles: %{
          # users who have followed you
          followers: %{stereotype: :followers},
          # users who you have followed
          followed: %{stereotype: :followed},
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
              # note that extra ACLs are added by `Bonfire.Boundaries.Users.default_visibility/0`
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
  end
end
