# ServerPlugins
Various shitty plugins for different needs.

## Radio Style Buy Menu for CS:GO

This plugin allows to create separate buy menu on server for classic game mode. Menu items in weapons menu and all item prices are customizible via configs.

Client commands:
```sm_buy / sm_buymenu (in console) / !buy / !buymenu (in chat) - Open buy menu.```

Server CVars:
```sm_buy_allow_taser (1 is default) - Allow to buy Zeus.
sm_buy_allow_tag (0 is default) - Allow to buy TA Grenade.
sm_buy_allow_asuit (0 is default) - Allow to buy Heavy Assault Suit.
sm_buy_allow_healthshot (0 is default) - Allow to buy Medi-Shot.
sm_buy_allow_shield (0 is default) - Allow to buy shield.
sm_assaultsuit_armor (200 is default) - Max amount of assault suit armor points.
```
Known issues:
- If client equipped custom weapon in inventory buy slot, stock weapon for this slot will be overwritten.
- Gloves in Heavy Assault Suit will be overlapped.

If you have any bug reports, bug fixes and code enhancements, create issue here.
