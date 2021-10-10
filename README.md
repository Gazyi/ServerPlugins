# ServerPlugins
Various shitty plugins for different needs.

## [CS:GO] Radio Style Buy Menu 

This plugin allows to create separate buy menu on server for classic game mode. Menu items in weapons menu and all item prices are customizible via configs.

Client commands:
```sm_buy / sm_buymenu (in console) / !buy / !buymenu (in chat) - Open buy menu.```

Server CVars:
```
sm_buy_allow_taser (Default value: 1) - Allow to buy Zeus.
sm_buy_allow_tag (Default value: 0) - Allow to buy TA Grenade.
sm_buy_allow_asuit (Default value: 0) - Allow to buy Heavy Assault Suit.
sm_buy_allow_healthshot (Default value: 0) - Allow to buy Medi-Shot.
sm_buy_allow_shield (Default value: 0) - Allow to buy shield.
sm_assaultsuit_armor (Default value: 200) - Max amount of assault suit armor points.
```
Known issues:
- If client equipped custom weapon in inventory buy slot, stock weapon for this slot will be overwritten.
- Equipping Heavy Assault Suit will make gloves fallback to default CT gloves, regardless of team.

## [Source MP/SDK 2013/CS:GO] Air Time

This plugin allows to control underwater time and disable drowning.

Server CVars:
```
sm_airtime_enabled (Default value: 1) - Enable Air Time Plugin.
sm_airtime_time (Default value: 12) - How many seconds players can be underwater without drowning. Negative number disables drowning.
sm_airtime_debug (Default value: 0) - Enable debug Mode.
```

If you have any bug reports, bug fixes and code enhancements, create issue here.
