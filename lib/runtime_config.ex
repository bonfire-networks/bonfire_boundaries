defmodule Bonfire.Boundaries.RuntimeConfig do
  @behaviour Bonfire.Common.ConfigModule
  def config_module, do: true

  @doc """
  NOTE: you can override this default config in your app's runtime.exs, by placing similarly-named config keys below the `Bonfire.Common.Config.LoadExtensionsConfig.load_configs` line
  """
  def config do
    import Config

    config :bonfire_boundaries,
      # you wouldn't want to do that.
      disabled: false

    ### Verbs are like permissions. Each represents some activity or operation that may or may not be able to perform.
    verbs = [
      #
      see: %{
        id: "0BSERV1NG11ST1NGSEX1STENCE",
        verb: "See",
        icon: "Heroicons-Solid:Eye",
        summary: "Discoverable in lists (like feeds)"
      },
      read: %{
        id: "0EAD1NGSVTTER1YFVNDAMENTA1",
        verb: "Read",
        icon: "bxs:BookReader",
        summary: "Readable/visible (if you can see or have a direct link)"
      },
      create: %{
        id: "4REATE0RP0STBRANDNEW0BJECT",
        verb: "Create",
        icon: "bxs:Pen",
        summary: "Create a post or other object"
      },
      edit: %{
        id: "4HANG1NGVA1VES0FPR0PERT1ES",
        verb: "Edit",
        icon: "bx:Highlight",
        summary: "Modify the contents of an existing object"
      },
      delete: %{
        id: "4AKESTVFFG0AWAYPERMANENT1Y",
        verb: "Delete",
        icon: "bxs:TrashAlt",
        summary: "Delete an object"
      },
      follow: %{
        id: "20SVBSCR1BET0THE0VTPVT0F1T",
        verb: "Follow",
        icon: "bx:Walk",
        summary: "Follow a user or thread or whatever"
      },
      like: %{
        id: "11KES1ND1CATEAM11DAPPR0VA1",
        verb: "Like",
        icon: "bxs:Star",
        summary: "Like an object (and notify the author)"
      },
      boost: %{
        id: "300ST0R0RANN0VCEANACT1V1TY",
        verb: "Boost",
        icon: "bx:Repost",
        summary: "Boost an object (and notify the author)"
      },
      flag: %{
        id: "71AGSPAM0RVNACCEPTAB1E1TEM",
        verb: "Flag",
        icon: "bxs:FlagAlt",
        summary:
          "Flag an object for a moderator to review (please note that anyone who can see or read something can flag it anyway)"
      },
      reply: %{
        id: "71TCREAT1NGA11NKEDRESP0NSE",
        verb: "Reply",
        icon: "bx:Reply",
        summary: "Reply to an activity or post"
      },
      mention: %{
        id: "0EFERENC1NGTH1NGSE1SEWHERE",
        verb: "Mention",
        icon: "bx:At",
        summary: "Mention a user or object (and notify them)"
      },
      tag: %{
        id: "4ATEG0R1S1NGNGR0VP1NGSTVFF",
        verb: "Tag",
        icon: "bxs:PurchaseTag",
        summary: "Tag a user or object, or publish in a topic"
      },
      label: %{
        id: "7PDATETHESTATVS0FS0METH1NG",
        verb: "Label",
        icon: "fluent:status-16-filled",
        summary: "Set/update a status or label"
      },
      message: %{
        id: "40NTACTW1THAPR1VATEMESSAGE",
        verb: "Message",
        icon: "bxs:Send",
        summary: "Send a message"
      },
      request: %{
        id: "1NEEDPERM1SS10NT0D0TH1SN0W",
        verb: "Request",
        icon: "humbleicons:user-asking",
        summary: "Request permission for another verb (eg. request to follow)"
      },
      schedule: %{
        id: "7SCHEDV1EF1XEDDES1REDDATES",
        verb: "Schedule",
        icon: "akar-icons:schedule",
        summary: "Set an expected or desired date"
      },
      pin: %{
        id: "1P1NN1NNG1S11KEH1GH11GHT1T",
        verb: "Pin",
        icon: "eos-icons:pin",
        summary: "Pin something to highlight it"
      },

      # WIP adding verbs, see: https://github.com/bonfire-networks/bonfire-app/issues/406

      toggle: %{
        id: "1CANENAB1E0RD1SAB1EFEATVRE",
        verb: "Toggle",
        icon: "bx:ToggleRight",
        summary: "Enable/disable extensions or features",
        scope: :instance
      },
      describe: %{
        id: "1CANADD0M0D1FY1NF0METADATA",
        verb: "Describe",
        icon: "bx:CommentEdit",
        summary: "Edit info and metadata, eg. thread titles",
        scope: :instance
      },
      grant: %{
        id: "1T0ADDED1TREM0VEB0VNDAR1ES",
        verb: "Grant",
        icon: "bx:Key",
        summary: "Add, edit or remove boundaries",
        scope: :instance
      },
      assign: %{
        id: "1T0ADDC1RC1ES0RASS1GNR01ES",
        verb: "Assign",
        icon: "bxs:UserBadge",
        summary: "Assign roles or tasks",
        scope: :instance
      },
      invite: %{
        id: "11NV1TESPE0P1E0RGRANTENTRY",
        verb: "Invite",
        icon: "bx:Gift",
        summary: "Invite users or grant entry",
        scope: :instance
      },
      mediate: %{
        id: "1T0SEEF1AGSANDMAKETHEPEACE",
        verb: "Mediate",
        icon: "bxs:FlagCheckered",
        summary: "See flags",
        scope: :instance
      },
      block: %{
        id: "1T0MANAGEB10CKGH0STS11ENCE",
        verb: "Block",
        icon: "bx:Block",
        summary: "Manage blocks",
        scope: :instance
      },
      configure: %{
        id: "1T0C0NF1GVREGENERA1SETT1NG",
        verb: "Configure",
        icon: "Heroicons-Solid:Adjustments",
        summary: "Change general settings",
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

    verbs_interact_minus_boost =
      verbs_see_read_request ++
        [
          :like,
          :follow
        ]

    verbs_interact_reply_minus_boost = verbs_interact_minus_boost ++ [:reply, :mention, :message]

    verbs_interact_incl_boost = verbs_interact_minus_boost ++ [:boost, :pin]
    verbs_interact_and_reply = verbs_interact_incl_boost ++ [:reply, :mention, :message]
    verbs_interact_and_contribute = verbs_interact_and_reply ++ [:create, :tag]

    public_acls = [
      :guests_may_see_read,
      :guests_may_read,
      :remotes_may_interact,
      :remotes_may_reply,
      :locals_may_read,
      :locals_may_interact,
      :locals_may_reply
    ]

    config :bonfire,
      verbs: verbs,
      role_verbs: [
        # Boost, Follow, Like, Mention, Pin, Read, Reply, Request, See, Tag
        none: [],
        read: verbs_see_read_request,
        interact: verbs_interact_incl_boost,
        participate: verbs_interact_and_reply,
        contribute: verbs_interact_and_contribute,
        caretaker: all_verb_names
      ],
      verbs_to_grant: [
        default: verbs_interact_and_reply,
        message: verbs_interact_reply_minus_boost
      ],
      # preset ACLs to show in smart input
      acls_to_present: [],
      # what boundaries we can display to everyone when applied on objects
      public_acls_on_objects: public_acls ++ [:guests_may_see],
      preset_acls: %{
        "public" => [
          :guests_may_see_read,
          :locals_may_reply,
          :remotes_may_reply
        ],
        "federated" => [:locals_may_reply],
        "local" => [:locals_may_reply]
      },
      preset_acls_all: %{
        "public" => [
          :guests_may_see,
          :guests_may_read,
          :guests_may_see_read,
          :remotes_may_interact,
          :remotes_may_reply
        ],
        "local" => [:locals_may_read, :locals_may_interact, :locals_may_reply]
      },
      create_verbs: [
        # block:  Bonfire.Data.Social.Block,
        boost: Bonfire.Data.Social.Boost,
        follow: Bonfire.Data.Social.Follow,
        flag: Bonfire.Data.Social.Flag,
        like: Bonfire.Data.Social.Like
      ]

    ### Now follows quite a lot of fixtures that must be inserted into the database.

    config :bonfire,
      ### Users are placed into one or more circles, either by users or by the system. Circles referenced in ACLs have the
      ### effect of applying to all users in those circles.
      circles: %{
        ### Public circles used to categorise broadly how much of a friend/do the user is.
        guest: %{id: "0AND0MSTRANGERS0FF1NTERNET", name: "Guests"},
        local: %{id: "3SERSFR0MY0VR10CA11NSTANCE", name: "Local Users"},
        activity_pub: %{
          id: "7EDERATEDW1THANACT1V1TYPVB",
          name: "ActivityPub Peers"
        },
        admin: %{id: "0ADM1NSVSERW1THSVPERP0WERS", name: "Instance Admins"},

        ### Stereotypes - placeholders for special per-user circles the system will manage.
        followers: %{
          id: "7DAPE0P1E1PERM1TT0F0110WME",
          name: "Those who follow me",
          stereotype: true
        },
        followed: %{
          id: "4THEPE0P1ES1CH00SET0F0110W",
          name: "Those I follow",
          stereotype: true
        },
        ghost_them: %{id: "7N010NGERC0NSENTT0Y0VN0WTY", name: "Those I ghosted", stereotype: true},
        silence_them: %{
          id: "7N010NGERWANTT011STENT0Y0V",
          name: "Those I silenced",
          stereotype: true
        },
        silence_me: %{
          id: "0KF1NEY0VD0N0TWANTT0HEARME",
          name: "Those who silenced me",
          stereotype: true
        }
      },
      ### ACLs (Access Control Lists) are reusable lists of permissions assigned to users and circles. Objects in bonfire
      ### have one or more ACLs attached and we combine the results of all of them to determine whether a user is permitted
      ### to perform a particular operation.
      acls: %{
        instance_care: %{
          id: "01SETT1NGSF0R10CA11NSTANCE",
          name: "Local instance roles & boundaries"
        },

        ### Public ACLs that allow basic control over visibility and interactions.
        guests_may_see_read: %{
          id: "7W1DE1YAVA11AB1ET0SEENREAD",
          name: "Publicly discoverable and readable"
        },
        guests_may_see: %{
          id: "50VCANF1NDMEBVTCAN0T0PENME",
          name: "Publicly discoverable, but contents may be hidden"
        },
        guests_may_read: %{
          id: "50VCANREAD1FY0VHAVETHE11NK",
          name: "Publicly readable, but not necessarily discoverable"
        },
        remotes_may_interact: %{
          id: "5REM0TEPE0P1E1NTERACTREACT",
          name: "Remote users may read and interact"
        },
        remotes_may_reply: %{
          id: "5REM0TEPE0P1E1NTERACTREP1Y",
          name: "Remote users may read, interact and reply"
        },
        locals_may_read: %{
          id: "10CA1SMAYSEEANDREAD0N1YN0W",
          name: "Visible to local users"
        },
        locals_may_interact: %{
          id: "710CA1SMY1NTERACTN0TREP1YY",
          name: "Local users may read and interact"
        },
        locals_may_reply: %{
          id: "710CA1SMY1NTERACTANDREP1YY",
          name: "Local users may read, interact and reply"
        },

        ### Stereotypes - placeholders for special per-user ACLs the system will manage.

        ## ACLs that confer my personal permissions on things i have created
        # i_may_read:            %{id: "71MAYSEEANDREADMY0WNSTVFFS", name: "I may read"},              # not currently used
        # i_may_interact:        %{id: "71MAY1NTERACTW1MY0WNSTVFFS", name: "I may read and interact"}, # not currently used
        i_may_administer: %{
          id: "71MAYADM1N1STERMY0WNSTVFFS",
          name: "I may administer",
          stereotype: true
        },

        ## ACLs that confer permissions for people i mention (or reply to, which causes a mention)
        # mentions_may_read:     %{id: "7MENT10NSCANREADTH1STH1NGS", name: "Mentions may read", stereotype: true},
        # mentions_may_interact: %{id: "7MENT10NSCAN1NTERACTW1TH1T", name: "Mentions may read and interact", stereotype: true},
        # mentions_may_reply:    %{id: "7MENT10NSCANEVENREP1YT01TS", name: "Mentions may read, interact and reply", stereotype: true},

        ## "Negative" ACLs that apply overrides for ghosting and silencing purposes.
        nobody_can_anything: %{
          id: "0H0STEDCANTSEE0RD0ANYTH1NG",
          name: "People I ghosted cannot see",
          stereotype: true
        },
        nobody_can_reach: %{
          id: "1S11ENCEDTHEMS0CAN0TP1NGME",
          name: "People I silenced aren't discoverable by me",
          stereotype: true
        },
        nobody_can_see: %{
          id: "2HEYS11ENCEDMES0CAN0TSEEME",
          name: "People who silenced me cannot discover me",
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
          admin: all_verb_names,
          local: verbs_interact_and_contribute,
          activity_pub: verbs_interact_incl_boost,
          guest: verbs_see_read_request
        },
        guests_may_see_read: %{guest: verbs_see_read_request},
        guests_may_see: %{guest: verbs_see_request},
        guests_may_read: %{guest: verbs_read_request},
        # interact but not reply
        remotes_may_interact: %{activity_pub: verbs_interact_incl_boost},
        # interact and reply
        remotes_may_reply: %{activity_pub: verbs_interact_and_reply},
        locals_may_read: %{local: verbs_see_read_request},
        # interact but not reply
        locals_may_interact: %{local: verbs_interact_incl_boost},
        # interact and reply
        locals_may_reply: %{local: verbs_interact_and_reply},
        # negative grants:
        nobody_can_anything: %{ghost_them: verbs_negative.(all_verb_names)},
        nobody_can_reach: %{
          silence_them: verbs_negative.([:mention, :message, :reply])
        },
        nobody_can_see: %{silence_me: verbs_negative.([:see])}
      }

    # end of global boundaries

    negative_grants = [
      # instance-wide negative permissions
      :nobody_can_anything,
      :nobody_can_reach,
      :nobody_can_see,
      # per-user negative permissions
      :they_cannot_anything,
      :they_cannot_reach,
      :they_cannot_see
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
          # users who have silenced me
          silence_me: %{stereotype: :silence_me}
        },
        acls: %{
          ## ACLs that confer my personal permissions on things i have created
          # i_may_read:           %{stereotype: :i_may_read},
          # i_may_reply:          %{stereotype: :i_may_interact},
          i_may_administer: %{stereotype: :i_may_administer},
          ## "Negative" ACLs that apply overrides for ghosting and silencing purposes.
          they_cannot_anything: %{stereotype: :nobody_can_anything},
          they_cannot_reach: %{stereotype: :nobody_can_reach},
          they_cannot_see: %{stereotype: :nobody_can_see}
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
          they_cannot_anything: %{ghost_them: verbs_negative.(all_verb_names)},
          # People/instances I silence can't ping me
          they_cannot_reach: %{
            silence_them: verbs_negative.([:mention, :message])
          },
          # People who silence me can't see me or my objects in feeds and such (but can still read them if they have a
          # direct link or come across my objects in a thread structure or such).
          they_cannot_see: %{silence_me: verbs_negative.([:see])}
        },
        ### This lets us control access to the user themselves (e.g. to view their profile or mention them)
        controlleds: %{
          SELF:
            [
              # positive permissions
              :locals_may_interact,
              :remotes_may_interact,
              :i_may_administer
              # note that extra ACLs are added by `Bonfire.Boundaries.Users.default_visibility/0`
            ] ++ negative_grants
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
  end
end
