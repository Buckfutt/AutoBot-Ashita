# AutoBot for Ashita v4

AutoBot is a Lua automation and multibox-control framework for **Final Fantasy XI** running through **Ashita v4**. It is the actively maintained Ashita successor to [FFXI-AutoBot for Windower](https://github.com/Buckfutt/FFXI-AutoBot).

It provides optional modules for following, targeting, pulling, combat, navigation, trusts, job automation, weapon skills, party management, and remote control of alternate characters.

> [!WARNING]
> Use at your own risk. You are responsible for complying with Final Fantasy XI's terms and policies, as well as Ashita's rules.

## Requirements

- [Ashita v4](https://www.ashitaxi.com/)
- The included **Movement** plugin, for navigation, following, approach, and movement-related features.
- **UberWarp** is optional, but is required for AutoBot's `/ab warp` and `/ab warpto` commands.

## Installation

1. Download or clone this repository.
2. Copy the repository's `addons/autobot` folder into your Ashita installation's `addons` folder.
3. Copy the repository's `plugins/movement` folder into your Ashita installation's `plugins` folder.
4. Start Final Fantasy XI through Ashita, then load the required components:

   ```text
   /load movement
   /addon load autobot
   ```

   Load UberWarp too if you plan to use warping:

   ```text
   /addon load uberwarp
   ```

5. In game, run `/ab help` to see the current command summary and `/ab ui` to open AutoBot's settings interface.

AutoBot stores per-character settings under `config/addons/AutoBot/` in your Ashita installation.

## Included modules

| Module | What it does |
| --- | --- |
| `general` | Party, mount, trade, rest, and other common character actions |
| `follow` | Follow a named player or the remote-command sender |
| `targeting` | Maintain a target list and automate target selection |
| `pulling` | Pull with ranged attacks, a spell, or an ability |
| `combat` | Attack, assist, approach, auto-face, and auto-engage controls |
| `autows` | Automatic weapon skills and skillchain controls |
| `jobs` | Job-specific automation modules |
| `casting` | Cast spells and use job abilities |
| `trusts` | Save, summon, release, and manage trust sets |
| `navigation` | Record and follow navigation paths, including loop/reverse/bounce modes |
| `uberwarp` | Forward warp requests to UberWarp |

## Commands

Base commands are `/ab`, `/autobot`, and `/bot`.

### Core

```text
/ab help                         Show the command summary.
/ab ui                           Open or close the AutoBot UI.
/ab save                         Save this character's settings.
/ab load                         Reload this character's settings.
/ab debug on|off                 Toggle debug output.
/ab stop                         Immediately safety-pause automation and movement.
/ab resume                       Resume automation after /ab stop.
/ab module <name> on|off|toggle  Enable, disable, or toggle a module.
/ab settings                     Show module states.
```

### Party, following, and interaction

```text
/ab follow <name>                Follow a player.
/ab followme                     Follow the command sender when used remotely.
/ab stopfollow                   Stop following.
/ab join | leave | disband        Manage party membership.
/ab invite <name>                Invite a player.
/ab passleader <name>            Transfer party leadership.
/ab mount <name> | mountup       Mount a named or default mount.
/ab dismount                     Dismount.
/ab warpring                     Equip and use a Warp Ring.
/ab trade <name> | accepttrade | canceltrade
```

### Targeting, pulling, and combat

```text
/ab target add|remove|list <name>
/ab target start|stop
/ab pull start|stop
/ab pull method spell|ability|ranged "action"
/ab pull timeout <seconds>
/ab attack | assist [name] | disengage
/ab combat autoengage|approach|autoface|autoassist on|off
/ab combat assisttarget <name>
/ab face <degrees>               Rotate by the supplied number of degrees.
```

### Navigation and warping

```text
/ab nav record <path>            Record a path.
/ab nav start <path>             Follow a recorded path.
/ab nav pause|resume|stop
/ab nav loop|reverse|bounce      Toggle playback behavior.
/ab nav list|details <path>|delete <path>
/ab move <yalms> <direction>     Make a relative movement.
/ab warp <type> <location> [index]
```

Warp commands are passed to UberWarp. For example:

```text
/ab warp hp Southern San d'Oria 2
```

### Jobs, magic, trusts, and weapon skills

```text
/ab job main|sub|<job> start|stop|enable|disable|toggle
/ab job <job> <command> [arguments...]
/ab job status
/ab cast <spell> [target]
/ab ability <ability> [target]
/ab stopcasting
/ab trust save|summon|random|create|add|remove|delete|release|releaseall|list
/ab autows on|off|ws|tp|aftermathtp|cooldown|aftermath|sc|open|close|chain|closews
```

Available job modules: BLM, BRD, BST, COR, DNC, DRG, DRK, GEO, MNK, NIN, PLD, PUP, RDM, RNG, RUN, SAM, SCH, SMN, THF, WAR, and WHM.

For example, configure Rune Fencer rune behavior with a job command such as:

```text
/ab job run dark dark
```

Each job module has its own supported commands. Use the job's UI window or `/ab job <job> status` to confirm that it is loaded and active.

## Remote commands

AutoBot can accept commands sent in party chat or by `/tell` from a whitelisted character. Add trusted characters first:

```text
/ab whitelist add <name>
/ab whitelist remove <name>
/ab whitelist list
```

Then send either form from the whitelisted character:

```text
!followme
bot followme
!assist
!cast "Warp II" <me>
!command /echo Hello from AutoBot
```

`!followme`, `!assist`, `!invite`, and `!passleader` use the remote-command sender when a target is not supplied. Remote commands are rate-limited and ignored unless the sender is whitelisted.

## Contributing

Bug reports, fixes, new job behavior, and documentation improvements are welcome. Please describe the exact command used, expected behavior, actual behavior, and any relevant Ashita console or chat output.

## License

This project is released under the [MIT License](LICENSE).

Final Fantasy XI is a trademark of Square Enix. Ashita and UberWarp belong to their respective authors. This project is unaffiliated with Square Enix or the Ashita project.
