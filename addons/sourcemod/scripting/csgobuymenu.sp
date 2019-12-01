#include <sourcemod>
#include <sdktools>
#include <smlib_findweapon>

#pragma semicolon 1
#pragma newdecls required

// Plugin definitions
#define PLUGIN_VERSION		"0.2"

public Plugin myinfo =
{
	name = "[CS:GO] Radio Style Buy Menu",
	author = "Gazyi (Code snippets by LumiStance, Grey83, Greyscale and SMLIB contributors)",
	description = "Customizable radio style buy menu.",
	version = PLUGIN_VERSION,
	url = "https://github.com/Gazyi/ServerPlugins"
};

// Constants
#define CS_SLOT_PRIMARY		0	/**< Primary weapon slot. */
#define CS_SLOT_SECONDARY	1	/**< Secondary weapon slot. */
#define CS_SLOT_KNIFE		2	/**< Knife slot. */
#define CS_SLOT_GRENADE		3	/**< Grenade slot (will only return one grenade). */
#define CS_SLOT_C4			4	/**< C4 slot. */

enum ItemType
{
	Type_Pistol,
	Type_Shotgun,
	Type_SMG,
	Type_Rifle,
	Type_SniperRifle,
	Type_Machinegun,
	Type_Knife,
	Type_Grenade,
	Type_Equipment,
	Type_None
};

enum Teams
{
	CS_TEAM_NONE,
	CS_TEAM_SPECTATOR,
	CS_TEAM_T,
	CS_TEAM_CT
};

#define HEGrenadeOffset 		14	// (14 * 4)
#define FlashbangOffset 		15	// (15 * 4)
#define SmokegrenadeOffset		16	// (16 * 4)
#define	IncenderyGrenadesOffset	17	// (17 * 4) Also Molotovs
#define	DecoyGrenadeOffset		18	// (18 * 4)
#define HPShotOffset			21	// (21 * 4)
#define	TAGrenadeOffset			22	// (22 * 4)

// Debug messages
bool bDebug = true;

// General plugin vars
int g_ConfigTimeStamp = -1;
bool bLateLoad = false;
bool g_BuyTimeEnded = false;

// Weapon Entity Members and Data
int m_ArmorValue = -1;
int m_bHasHelmet = -1;
int m_bHasDefuser = -1;
int m_MoneyAmount = -1;
int offs_iItem = -1;

int TotalNades;
int FBLimit;
int GrenadeTypeLimit;
int HPShotsLimit;

// Exsiting CVar handles
Handle GrenadeAmmoTotal = null;
Handle GrenadeFBAmmo = null;
Handle GrenadeAmmo = null;
Handle HPShotsAmmo = null;

// Buy zone timer handle and variable
float fbuytime;
Handle BuyTimeTimer = null;

// Plugin CVar handles
Handle g_AllowTAGrenade = null;
Handle g_AllowAssaultSuit = null;
Handle g_AllowHealthshot = null;
Handle g_AllowTaser = null;
Handle g_ASuitArmor = null;
Handle g_AllowShield = null;

// Default Equipment prices
int g_VestPrice = 650;
int g_HelmetPrice = 350;
int g_VestHelmetPrice = 1000;
int g_ASuitPrice = 6000;
int g_DefuseKitPrice = 400;
int g_TaserPrice = 200;
int g_HPShotPrice = 800;
int g_ShieldPrice = 2200;

// Default Grenade prices
int g_HEPrice = 300;
int g_FBPrice = 200;
int g_SGPrice = 300;
int g_DCPrice = 50;
int g_IncPrice = 600;
int g_MolPrice = 400;
int g_TAGPrice = 500;

// Original player hands for Heavy Assault Suit revert
char g_PlayerHandsModel[MAXPLAYERS+1][PLATFORM_MAX_PATH];

// Parsing weapons config handle
Handle WeaponConfigHandle = null;

// Weapon Menu Configuration
#define MAX_WEAPON_COUNT 64
#define SHOW_MENU -1
int g_WeaponsCount;

char g_Weapons[MAX_WEAPON_COUNT][32];
int g_WeaponIDs[MAX_WEAPON_COUNT];
int g_Prices[MAX_WEAPON_COUNT];

// Buy Menu handles
bool g_MenuOpen[MAXPLAYERS+1] = {false, ...};
Handle g_Mainmenu = null;
Handle g_Pistolmenu = null;
Handle g_Shotgunmenu = null;
Handle g_SMGmenu = null;
Handle g_Riflemenu = null;
Handle g_MGmenu = null;
Handle g_Equipmentmenu = null;
Handle g_Grenadesmenu = null;

// Player's Weapon buy menu IDs
int g_PlayerPrimary[MAXPLAYERS+1] = {-1, ...};
int g_PlayerSecondary[MAXPLAYERS+1] = {-1, ...};
int g_PlayerOldPrimary[MAXPLAYERS+1] = {-1, ...};
int g_PlayerOldSecondary[MAXPLAYERS+1] = {-1, ...};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	bLateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	// Cache Send Property Offsets
	m_ArmorValue = FindSendPropInfo("CCSPlayer", "m_ArmorValue");
	m_bHasHelmet = FindSendPropInfo("CCSPlayer", "m_bHasHelmet");
	m_bHasDefuser = FindSendPropInfo("CCSPlayer", "m_bHasDefuser");
	m_MoneyAmount = FindSendPropInfo("CCSPlayer", "m_iAccount");
	offs_iItem = FindSendPropInfo("CBaseCombatWeapon", "m_iItemDefinitionIndex");
	if (m_ArmorValue == -1 || m_bHasHelmet == -1 || m_bHasDefuser == -1 || m_MoneyAmount == -1) SetFailState("\nFailed to retrieve entity member offsets");

	// Client Commands
	RegConsoleCmd("sm_buy", Command_BuyMenu);
	RegConsoleCmd("sm_buymenu", Command_BuyMenu);
	
	// Server CVars
	g_AllowTAGrenade = CreateConVar("sm_buy_allow_tag", "0", "Allow to buy TA Grenade.", FCVAR_NOTIFY);
	g_AllowAssaultSuit = CreateConVar("sm_buy_allow_asuit", "0", "Allow to buy Heavy Assault Suit.", FCVAR_NOTIFY);
	g_AllowHealthshot = CreateConVar("sm_buy_allow_healthshot", "0", "Allow to buy Medi-Shot.", FCVAR_NOTIFY);
	g_AllowShield = CreateConVar("sm_buy_allow_shield", "0", "Allow to buy shield.", FCVAR_NOTIFY);
	g_AllowTaser = CreateConVar("sm_buy_allow_taser", "1", "Allow to buy Zeus.", FCVAR_NOTIFY);
	g_ASuitArmor = CreateConVar("sm_assaultsuit_armor", "200", "Max amount of assault suit armor points.", FCVAR_NOTIFY);
	
	// Event Hooks
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_team", Event_PlayerTeam);
	HookEvent("item_pickup", Event_ItemPickup);
	HookEvent("round_start", Event_RoundStart);
	//HookEvent("buytime_ended", Event_BuyTimeEnded);
	HookEvent("exit_buyzone", Event_ExitBuyZone);
	
	if (bLateLoad)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i)) continue;

			OnClientPutInServer(i);
		}
	}
}

public void OnPluginEnd()
{
	CancelMenu(g_Mainmenu);
	CheckCloseHandle(g_Mainmenu);
}

public void OnMapStart()
{
	// Load configuration
	CheckConfig("configs/buymenu.ini");
	
	PrecacheSound("survival/armor_pickup_01.wav" , true);
	PrecacheSound("items/pickup_quiet_01.wav" , true);
	PrecacheSound("ui/weapon_cant_buy.wav" , true);
	PrecacheModel("models/player/custom_player/legacy/ctm_heavy.mdl", true);
	PrecacheModel("models/weapons/v_models/arms/ctm_heavy/v_sleeve_ctm_heavy.mdl", true);
	//PrecacheModel("models/weapons/ct_arms_ctm_heavy.mdl", true);
	PrecacheModel("models/player/custom_player/legacy/tm_phoenix_heavy.mdl", true);
	PrecacheModel("models/weapons/v_models/arms/phoenix_heavy/v_sleeve_phoenix_heavy.mdl", true);
	//PrecacheModel("models/weapons/t_arms_phoenix_heavy.mdl", true);
	
	// Handle late load
	if (GetClientCount(true))
		for (int client_index = 1; client_index <= MaxClients; ++client_index)
			if (IsClientInGame(client_index))
			{
				OnClientPutInServer(client_index);
				if (IsPlayerAlive(client_index)) CreateTimer(0.1, Event_HandleSpawn, GetClientUserId(client_index));
			}
	InitializeMainMenu();
	BuyTimeTimer = null;
}

public Action Event_RoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	g_BuyTimeEnded = false;
	PrintToServer("Custom buy menu active. Players can buy.");
	if (BuyTimeTimer) KillTimer(BuyTimeTimer);
	if (GameRules_GetProp("m_bWarmupPeriod") != 1) 
    {
		ConVar buytimecvar;
		ConVar freezetimecvar;
		buytimecvar = FindConVar("mp_buytime");
		freezetimecvar = FindConVar("mp_freezetime");
		fbuytime = buytimecvar.FloatValue + freezetimecvar.FloatValue; //Sum of mp_freezetime and mp_buytime.
		if ( fbuytime > 0 )
		{
			BuyTimeTimer = CreateTimer(fbuytime, Event_TimerBuyTimeEnded, GetEventInt(event, "userid"), TIMER_FLAG_NO_MAPCHANGE);
		}
	}
}

// For unknown reason Event_BuyTimeEnded event fires only at first round. That's why there's this workaround with timer.
public Action Event_TimerBuyTimeEnded(Handle timer, int user_index)
{
	g_BuyTimeEnded = true;
	int client_index = GetClientOfUserId(user_index);
	BuyTimeTimer = null;
	PrintToServer("Custom buy menu disabled. Buy time expired.");
	//Close all opened menus
	CloseBuyMenu(client_index);
}

public Action Event_ExitBuyZone(Handle event, const char[] name, bool dontBroadcast)
{
	//Close all opened menus
	int client_index = GetClientOfUserId(GetEventInt(event, "userid"));
	CloseBuyMenu(client_index);
}

public void CloseBuyMenu(int client_index)
{
	CancelClientMenu(client_index);	// Delayed
	g_MenuOpen[client_index] = false;
}

public void Event_PlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	int client_index = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!client_index || IsFakeClient(client_index)) return;
	if (!IsPlayerAlive(client_index))
	{
		g_PlayerOldPrimary[client_index] = -1;
		g_PlayerPrimary[client_index] = -1;
		g_PlayerOldSecondary[client_index] = -1;
		g_PlayerSecondary[client_index] = -1;
	}
}

public Action Event_ItemPickup(Handle event, const char[] name, bool dontbroadcast)
{
	int client_index = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!client_index || IsFakeClient(client_index)) return;
	CheckPrimWeaponSlot(client_index);
	CheckSecWeaponSlot(client_index);
}

stock void CheckConfig(const char[] ini_file)
{
	char file[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, file, sizeof(file), ini_file);

	int timestamp = GetFileTime(file, FileTime_LastChange);

	if (timestamp == -1) SetFailState("\nCould not stat config file: %s.", file);

	if (timestamp != g_ConfigTimeStamp)
	{
		InitializeMenus();
		if (ParseConfigFile(file))
		{
			g_ConfigTimeStamp = timestamp;
		}
	}
}

void InitializeMenus()
{
	g_WeaponsCount = 0;
	CheckCloseHandle(g_Pistolmenu);
	g_Pistolmenu = CreateMenu(MenuHandler_ChoosePistol, MenuAction_Display|MenuAction_DrawItem|MenuAction_Select|MenuAction_Cancel);

	CheckCloseHandle(g_Shotgunmenu);
	g_Shotgunmenu = CreateMenu(MenuHandler_ChoosePrimary, MenuAction_Display|MenuAction_DrawItem|MenuAction_Select|MenuAction_Cancel);
	
	CheckCloseHandle(g_SMGmenu);
	g_SMGmenu = CreateMenu(MenuHandler_ChoosePrimary, MenuAction_Display|MenuAction_DrawItem|MenuAction_Select|MenuAction_Cancel);
	
	CheckCloseHandle(g_Riflemenu);
	g_Riflemenu = CreateMenu(MenuHandler_ChooseRifle, MenuAction_Display|MenuAction_DrawItem|MenuAction_Select|MenuAction_Cancel);
	
	CheckCloseHandle(g_MGmenu);
	g_MGmenu = CreateMenu(MenuHandler_ChoosePrimary, MenuAction_Display|MenuAction_DrawItem|MenuAction_Select|MenuAction_Cancel);
}

bool ParseConfigFile(const char[] file) 
{
	// Set Defaults
	ParseWeaponConfigFile();
	Handle parser = SMC_CreateParser();
	SMC_SetReaders(parser, Config_NewSection, Config_UnknownKeyValue, Config_EndSection);
	SMC_SetParseEnd(parser, Config_End);

	int line = 0;
	int col = 0;
	char error[128];
	SMCError result = SMC_ParseFile(parser, file, line, col);
	CloseHandle(parser);

	if (result != SMCError_Okay) {
		SMC_GetErrorString(result, error, sizeof(error));
		LogError("%s on line %d, col %d of %s", error, line, col, file);
	}

	return (result == SMCError_Okay);
}

int g_configLevel;
public SMCResult Config_NewSection(Handle parser, const char[] section, bool quotes)
{
	g_configLevel++;
	if (g_configLevel==2)
	{
		if (StrEqual("Equipment", section, false)) SMC_SetReaders(parser, Config_NewSection, Config_EquipmentKeyValue, Config_EndSection);
		else if (StrEqual("Grenades", section, false)) SMC_SetReaders(parser, Config_NewSection, Config_GrenadesKeyValue, Config_EndSection);
	}
	else SMC_SetReaders(parser, Config_NewSection, Config_UnknownKeyValue, Config_EndSection);
	return SMCParse_Continue;
}

public SMCResult Config_UnknownKeyValue(Handle parser, const char[] key, const char[] value, bool key_quotes, bool value_quotes)
{
	SetFailState("\nDidn't recognize configuration: Level %i %s=%s", g_configLevel, key, value);
	return SMCParse_Continue;
}

public SMCResult Config_EquipmentKeyValue(Handle parser, const char[] key, const char[] value, bool key_quotes, bool value_quotes)
{
	if (StrEqual("Vest", key, false)) g_VestPrice = StringToInt(value);
	else if (StrEqual("Helmet", key, false)) g_HelmetPrice = StringToInt(value);
	else if (StrEqual("VestHelmet", key, false)) g_ASuitPrice = StringToInt(value);
	else if (StrEqual("AssaultSuit", key, false)) g_ASuitPrice = StringToInt(value);
	else if (StrEqual("Defuser", key, false)) g_DefuseKitPrice = StringToInt(value);
	else if (StrEqual("Taser", key, false)) g_TaserPrice = StringToInt(value);
	else if (StrEqual("Healthshot", key, false)) g_HPShotPrice = StringToInt(value);
	else if (StrEqual("Shield", key, false)) g_ShieldPrice = StringToInt(value);
	return SMCParse_Continue;
}

public SMCResult Config_GrenadesKeyValue(Handle parser, const char[] key, const char[] value, bool key_quotes, bool value_quotes)
{
	if (StrEqual("HEGrenade", key, false)) g_HEPrice = StringToInt(value);
	else if (StrEqual("Flashbang", key, false)) g_FBPrice = StringToInt(value);
	else if (StrEqual("SmokeGrenade", key, false)) g_SGPrice = StringToInt(value);
	else if (StrEqual("DecoyGrenade", key, false)) g_DCPrice = StringToInt(value);
	else if (StrEqual("IncendiaryGrenade", key, false)) g_IncPrice = StringToInt(value);
	else if (StrEqual("Molotov", key, false)) g_MolPrice = StringToInt(value);
	else if (StrEqual("TAGrenade", key, false)) g_TAGPrice = StringToInt(value);
	return SMCParse_Continue;
}

public SMCResult Config_EndSection(Handle parser)
{
	g_configLevel--;
	SMC_SetReaders(parser, Config_NewSection, Config_UnknownKeyValue, Config_EndSection);
	return SMCParse_Continue;
}

public void Config_End(Handle parser, bool halted, bool failed)
{
	if (failed) SetFailState("\nPlugin configuration error");
}

void ParseWeaponConfigFile()
{
	if (WeaponConfigHandle != null)
    {
        CloseHandle(WeaponConfigHandle);
    }
	
	WeaponConfigHandle = CreateKeyValues("Weapons");
    
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/buymenu_weapons.ini");
    
	if (!FileToKeyValues(WeaponConfigHandle, path))
    {
        SetFailState("\"%s\" missing from server", path);
    }
	
	char weaponid[8];
	char weaponname[64];
	char weapontype[64];
	
	KvRewind(WeaponConfigHandle);
	if (KvGotoFirstSubKey(WeaponConfigHandle))
    {
        do
        {
			if (g_WeaponsCount>=MAX_WEAPON_COUNT) SetFailState("\nToo many weapons declared!");
			
			KvGetSectionName(WeaponConfigHandle, weaponid, sizeof(weaponid));
			KvGetString(WeaponConfigHandle, "item_name", weaponname, sizeof(weaponname));
			g_WeaponIDs[g_WeaponsCount] = KvGetNum(WeaponConfigHandle, "weaponid");
			KvGetString(WeaponConfigHandle, "weapon", g_Weapons[g_WeaponsCount], sizeof(g_Weapons[]));
			KvGetString(WeaponConfigHandle, "weapon_type", weapontype, sizeof(weapontype));
			g_Prices[g_WeaponsCount] = KvGetNum(WeaponConfigHandle, "in game price");

			char display[64];
			Format(display, sizeof(display), "%s - %d$", weaponname, g_Prices[g_WeaponsCount]);
			if (StrEqual("Pistol", weapontype, false))
			{
				AddBuyMenuItem(g_Pistolmenu, weaponid, weaponname, g_Prices[g_WeaponsCount]);
			}
			else if (StrEqual("Shotgun", weapontype, false))
			{
				AddBuyMenuItem(g_Shotgunmenu, weaponid, weaponname, g_Prices[g_WeaponsCount]);
			}
			else if (StrEqual("SubMachinegun", weapontype, false))
			{
				AddBuyMenuItem(g_SMGmenu, weaponid, weaponname, g_Prices[g_WeaponsCount]);
			}
			else if (StrEqual("Rifle", weapontype, false))
			{
				AddBuyMenuItem(g_Riflemenu, weaponid, weaponname, g_Prices[g_WeaponsCount]);
			}
			else if (StrEqual("Machinegun", weapontype, false))
			{
				AddBuyMenuItem(g_MGmenu, weaponid, weaponname, g_Prices[g_WeaponsCount]);
			}
			g_WeaponsCount++;
        } 
		while (KvGotoNextKey(WeaponConfigHandle));
    }
}

stock int GetWeaponTeam(const char[] weaponid)
{
	KvRewind(WeaponConfigHandle);
	if (!KvJumpToKey(WeaponConfigHandle, weaponid))
	{
		return -1;
	}
	char weaponteam[8];
	KvGetString(WeaponConfigHandle, "team", weaponteam, sizeof(weaponteam), "any");
	if (StrEqual("t", weaponteam, false))
	{
		return 1;
	}
	else if (StrEqual("ct", weaponteam, false))
	{
		return 2;
	}
	else
	{
		return 0;
	}
}

// Handle for pistol menu
public int MenuHandler_ChoosePistol(Handle menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Display)
	{
		g_MenuOpen[param1] = true;
	}
	else if (action == MenuAction_DrawItem)
	{
		int client_index = param1;
		char weaponid[8];
		GetMenuItem(menu, param2, weaponid, sizeof(weaponid));
		int weapon_index = StringToInt(weaponid);
		int client_team = GetClientTeam(client_index);
		if (bDebug)
		{
			PrintToServer("ID %d, team: %d", weapon_index, GetWeaponTeam(weaponid));
		}
		if ((GetWeaponTeam(weaponid) == 2) && (view_as<Teams>(client_team) == CS_TEAM_T))
		{
			return ITEMDRAW_IGNORE;
		}
		else if ((GetWeaponTeam(weaponid) == 1) && (view_as<Teams>(client_team) == CS_TEAM_CT))
		{
			return ITEMDRAW_IGNORE;
		}
	}
	else if (action == MenuAction_Select)
	{
		int client_index = param1;
		char weaponid[8];
		GetMenuItem(menu, param2, weaponid, sizeof(weaponid));
		int weapon_index = StringToInt(weaponid);
		weapon_index = weapon_index-1;
		if (bDebug)
		{
			PrintToServer("Client %d selected ID %d, entity: %s", param1, weapon_index, g_Weapons[weapon_index]);
		}
		g_PlayerOldSecondary[client_index] = g_PlayerSecondary[client_index];
		g_PlayerSecondary[client_index] = weapon_index;
		if (bDebug)
		{
			PrintToServer("Client old secondary ID: %d, New ID: %d", g_PlayerOldSecondary[client_index], g_PlayerSecondary[client_index]);
		}
		if (g_PlayerOldSecondary[client_index] == g_PlayerSecondary[client_index])
		{
			if (bDebug)
			{
				PrintToServer("Client old secondary ID: %d, New ID: %d", g_PlayerOldSecondary[client_index], g_PlayerSecondary[client_index]);
			}
			PrintHintText(client_index, "#Cstrike_Already_Own_Weapon");
			EmitSoundToClient(client_index, "ui/weapon_cant_buy.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);
			return 0;
		}
		if (view_as<Teams>(GetClientTeam(client_index)) > CS_TEAM_SPECTATOR)
		{
			if (!TakePlayerMoney(client_index, g_Prices[weapon_index]))
			{
				g_PlayerSecondary[client_index] = g_PlayerOldSecondary[client_index];
				if (bDebug)
				{
					PrintToServer("Client don't have enough money for selected ID %d, reset back to ID %d.", weapon_index, g_PlayerSecondary[client_index]);
				}
				return 0;
			}
			GiveSecondary(client_index);
		}
	}
	else if (action == MenuAction_Cancel) g_MenuOpen[param1] = false;
	return 0;
}

// Handle for Primary menus
public int MenuHandler_ChoosePrimary(Handle menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Display)
	{
		g_MenuOpen[param1] = true;
	}
	else if (action == MenuAction_DrawItem)
	{
		int client_index = param1;
		char weaponid[8];
		GetMenuItem(menu, param2, weaponid, sizeof(weaponid));
		int weapon_index = StringToInt(weaponid);
		int client_team = GetClientTeam(client_index);
		if (bDebug)
		{
			PrintToServer("ID %d, team: %d", weapon_index, GetWeaponTeam(weaponid));
		}
		if ((GetWeaponTeam(weaponid) == 2) && (view_as<Teams>(client_team) == CS_TEAM_T))
		{
			return ITEMDRAW_IGNORE;
		}
		else if ((GetWeaponTeam(weaponid) == 1) && (view_as<Teams>(client_team) == CS_TEAM_CT))
		{
			return ITEMDRAW_IGNORE;
		}
	}
	else if (action == MenuAction_Select)
	{
		int client_index = param1;
		char weaponid[8];
		GetMenuItem(menu, param2, weaponid, sizeof(weaponid));
		int weapon_index = StringToInt(weaponid);
		weapon_index = weapon_index-1;
		if (bDebug)
		{
			PrintToServer("Client %d selected ID %d, entity: %s", param1, weapon_index, g_Weapons[weapon_index]);
		}
		g_PlayerOldPrimary[client_index] = g_PlayerPrimary[client_index];
		g_PlayerPrimary[client_index] = weapon_index;
		if (g_PlayerOldPrimary[client_index] == g_PlayerPrimary[client_index])
		{
			if (bDebug)
			{
				PrintToServer("Client old secondary ID: %d, New ID: %d", g_PlayerOldSecondary[client_index], g_PlayerSecondary[client_index]);
			}
			PrintHintText(client_index, "#Cstrike_Already_Own_Weapon");
			EmitSoundToClient(client_index, "ui/weapon_cant_buy.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);
			return 0;
		}
		if (view_as<Teams>(GetClientTeam(client_index)) > CS_TEAM_SPECTATOR)
		{
			if (!TakePlayerMoney(client_index, g_Prices[weapon_index]))
			{
				g_PlayerPrimary[client_index] = g_PlayerOldPrimary[client_index];
				if (bDebug)
				{
					PrintToServer("Client don't have enough money for selected ID %d, reset back to ID %d.", weapon_index, g_PlayerPrimary[client_index]);
				}
				return 0;
			}
			GivePrimary(client_index);
		}
	}
	else if (action == MenuAction_Cancel) g_MenuOpen[param1] = false;
	return 0;
}

// Handle for Rifle menu (because heavy assault suit doesn't allow to buy rifles)
public int MenuHandler_ChooseRifle(Handle menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Display)
	{
		g_MenuOpen[param1] = true;
	}
	else if (action == MenuAction_DrawItem)
	{
		int client_index = param1;
		char weaponid[8];
		GetMenuItem(menu, param2, weaponid, sizeof(weaponid));
		int weapon_index = StringToInt(weaponid);
		int client_team = GetClientTeam(client_index);
		if (bDebug)
		{
			PrintToServer("ID %d, team: %d", weapon_index, GetWeaponTeam(weaponid));
		}
		if ((GetWeaponTeam(weaponid) == 2) && (view_as<Teams>(client_team) == CS_TEAM_T))
		{
			return ITEMDRAW_IGNORE;
		}
		else if ((GetWeaponTeam(weaponid) == 1) && (view_as<Teams>(client_team) == CS_TEAM_CT))
		{
			return ITEMDRAW_IGNORE;
		}
	}
	else if (action == MenuAction_Select)
	{
		int client_index = param1;
		if (GetEntProp(client_index, Prop_Send, "m_bHasHeavyArmor"))
		{
			PrintHintText(client_index, "#SFUI_BuyMenu_HeavyAssaultSuitRestriction");
			EmitSoundToClient(client_index, "ui/weapon_cant_buy.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);
			return 0;
		}
		char weaponid[8];
		GetMenuItem(menu, param2, weaponid, sizeof(weaponid));
		int weapon_index = StringToInt(weaponid);
		weapon_index = weapon_index-1;
		if (bDebug)
		{
			PrintToServer("Client %d selected ID %d, entity: %s", param1, weapon_index, g_Weapons[weapon_index]);
		}
		g_PlayerOldPrimary[client_index] = g_PlayerPrimary[client_index];
		g_PlayerPrimary[client_index] = weapon_index;
		if (g_PlayerOldPrimary[client_index] == g_PlayerPrimary[client_index])
		{
			if (bDebug)
			{
				PrintToServer("Client old secondary ID: %d, New ID: %d", g_PlayerOldSecondary[client_index], g_PlayerSecondary[client_index]);
			}
			PrintHintText(client_index, "#Cstrike_Already_Own_Weapon");
			EmitSoundToClient(client_index, "ui/weapon_cant_buy.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);
			return 0;
		}
		if (view_as<Teams>(GetClientTeam(client_index)) > CS_TEAM_SPECTATOR)
		{
			if (!TakePlayerMoney(client_index, g_Prices[weapon_index]))
			{
				g_PlayerPrimary[client_index] = g_PlayerOldPrimary[client_index];
				if (bDebug)
				{
					PrintToServer("Client don't have enough money for selected ID %d, reset back to ID %d.", weapon_index, g_PlayerPrimary[client_index]);
				}
				return 0;
			}
			GivePrimary(client_index);
		}
	}
	else if (action == MenuAction_Cancel) g_MenuOpen[param1] = false;
	return 0;
}

void GivePrimary(int client_index)
{
	int old_weapon_index = g_PlayerOldPrimary[client_index];
	int weapon_index = g_PlayerPrimary[client_index];
	RemoveWeaponBySlot(client_index, CS_SLOT_PRIMARY);
	if (weapon_index >= 0 && weapon_index < g_WeaponsCount) GivePlayerItem(client_index, g_Weapons[weapon_index]);
	if (old_weapon_index >= 0 && old_weapon_index < g_WeaponsCount)	GivePlayerItem(client_index, g_Weapons[old_weapon_index]);
}

void GiveSecondary(int client_index)
{
	int old_weapon_index = g_PlayerOldSecondary[client_index];
	int weapon_index = g_PlayerSecondary[client_index];
	RemoveWeaponBySlot(client_index, CS_SLOT_SECONDARY);
	if (weapon_index >= 0 && weapon_index < g_WeaponsCount) GivePlayerItem(client_index, g_Weapons[weapon_index]);
	if (old_weapon_index >= 0 && old_weapon_index < g_WeaponsCount)	GivePlayerItem(client_index, g_Weapons[old_weapon_index]);
}

bool RemoveWeaponBySlot(int client_index, int slot)
{
	int entity_index = GetPlayerWeaponSlot(client_index, slot);
	if (entity_index>0)
	{
		RemovePlayerItem(client_index, entity_index);
		AcceptEntityInput(entity_index, "Kill");
		return true;
	}
	return false;
}

// Must be manually replayed for late load
public void OnClientPutInServer(int client_index)
{
	g_MenuOpen[client_index]=false;
}

public void Event_PlayerSpawn(Handle event, const char[] name, bool dontBroadcast)
{
	CreateTimer(0.1, Event_HandleSpawn, GetEventInt(event, "userid"));
}

public Action CS_OnCSWeaponDrop(int client_index, int weaponIndex)
{
	RequestFrame(CheckPrimWeaponSlot, client_index);
	RequestFrame(CheckSecWeaponSlot, client_index);
}

public void CheckPrimWeaponSlot(int client_index)
{
	int entity_index = GetPlayerWeaponSlot(client_index, CS_SLOT_PRIMARY);
	if (entity_index>0)
	{
		//Find entity weapon ID in "weaponID" array and set weapon index.
		int item_index;
		int weapon_index;
		char sBuffer[64];
		GetEntityClassname(entity_index, sBuffer, 64);
		if (bDebug)
		{
			PrintToServer("Classname: %s", sBuffer);
		}
		if(offs_iItem != -1) //Can't be -1, unless there's no weapon?
		{
			item_index = GetEntData(entity_index, offs_iItem);
			IntToString(item_index, sBuffer, 64);
			if (bDebug)
			{
				PrintToServer("Item Schema ID: %s", sBuffer);
			}
			for (int i = 0; i <= MAX_WEAPON_COUNT; ++i) 
			{ 
				if (g_WeaponIDs[i] == item_index)
				{
					g_PlayerPrimary[client_index] = i;
					break;
				}
			}
			weapon_index = g_PlayerPrimary[client_index];
			if (bDebug)
			{
				PrintToServer("Client %d have %s as primary weapon.", client_index, g_Weapons[weapon_index]);
			}
		}
		return;
	}
	else
	{
		g_PlayerPrimary[client_index] = -1;
		if (bDebug)
		{
			PrintToServer("Client %d have no primary weapon.", client_index);
		}
		return;
	}
}

public void CheckSecWeaponSlot(int client_index)
{
	int entity_index = GetPlayerWeaponSlot(client_index, CS_SLOT_SECONDARY);
	/*if (!IsFakeClient(client_index))
	{
		PrintToServer("Client %d have %d entity as secondary.", client_index, entity_index);
	}*/
	if (entity_index>0)
	{
		//Find entity weapon ID in "weaponID" array and set weapon index.
		int item_index;
		int weapon_index;
		char sBuffer[64];
		GetEntityClassname(entity_index, sBuffer, 64);
		if (bDebug)
		{
			PrintToServer("Classname: %s", sBuffer);
		}
		if(offs_iItem != -1) //Can't be -1, unless there's no weapon?
		{
			item_index = GetEntData(entity_index, offs_iItem);
			IntToString(item_index, sBuffer, 64);
			if (bDebug)
			{
				PrintToServer("Item Schema ID: %s", sBuffer);
			}
			for (int i = 0; i <= MAX_WEAPON_COUNT; ++i) 
			{ 
				if (g_WeaponIDs[i] == item_index)
				{
					g_PlayerSecondary[client_index] = i;
					break;
				}
			}
			weapon_index = g_PlayerSecondary[client_index];
			if (bDebug)
			{
				PrintToServer("Client %d have %s as secondary weapon.", client_index, g_Weapons[weapon_index]);
			}
		}
		return;
	}
	else
	{
		g_PlayerSecondary[client_index] = -1;
		if (bDebug)
		{
			PrintToServer("Client %d have no secondary weapon.", client_index);
		}
		return;
	}
}

// If player spectated close any gun menus
public void Event_PlayerTeam(Handle event, const char[] name, bool dontBroadcast)
{
	int client_index = GetClientOfUserId(GetEventInt(event, "userid"));

	if (g_MenuOpen[client_index] && (view_as<Teams>(GetEventInt(event, "team")) == CS_TEAM_SPECTATOR))
	{
		CancelClientMenu(client_index);	// Delayed
		g_MenuOpen[client_index] = false;
	}
}

// Handle for main menu
public int MenuHandler_Mainmenu(Handle menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Display) g_MenuOpen[param1] = true;
	else if (action == MenuAction_Select)
	{
		char info[32];
		GetMenuItem(menu, param2, info, sizeof(info));
		if (StrEqual(info, "PistolCat"))
		{
			Show_Submenu(g_Pistolmenu, param1, MENU_TIME_FOREVER);
		}	
		if (StrEqual(info, "ShotgunCat"))
		{
			Show_Submenu(g_Shotgunmenu, param1, MENU_TIME_FOREVER);
		}
		if (StrEqual(info, "SMGCat"))
		{
			Show_Submenu(g_SMGmenu, param1, MENU_TIME_FOREVER);
		}	
		if (StrEqual(info, "RifleCat"))
		{
			Show_Submenu(g_Riflemenu, param1, MENU_TIME_FOREVER);
		}
		if (StrEqual(info, "MGCat"))
		{
			Show_Submenu(g_MGmenu, param1, MENU_TIME_FOREVER);
		}
		if (StrEqual(info, "OpenGrenadeMenu"))
		{
			Show_GrenadeMenu( param1, MENU_TIME_FOREVER );
		}
		if (StrEqual(info, "EquipmentCat"))
		{
			Show_EquipMenu( param1, MENU_TIME_FOREVER );
		}
		else
		{
			if (bDebug)
			{
				PrintToServer("Client %d selected %s", param1, info);
			}
		}
	}
	else if (action == MenuAction_Cancel)
	{
		g_MenuOpen[param1] = false;
	}
}

// Handle for Equipment menu
public int MenuHandler_Equipment(Handle menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Display) g_MenuOpen[param1] = true;
	else if (action == MenuAction_Select)
	{
		char info[32];
		GetMenuItem(menu, param2, info, sizeof(info));
		if (StrEqual(info, "Vest"))
		{
			Buy_Armor( param1 );
		}
		if (StrEqual(info, "VestHelmet"))
		{
			Buy_ArmorHelmet( param1 );
		}
		if (StrEqual(info, "AssaultSuit"))
		{
			Buy_AssaultSuit( param1 );
		}
		if (StrEqual(info, "TacShield"))
		{
			Buy_Shield( param1 );
		}
		if (StrEqual(info, "Defuser"))
		{
			Buy_Defusekit( param1 );
		}
		if (StrEqual(info, "HealthShot"))
		{
			Buy_Healthshot( param1 );
		}
		if (StrEqual(info, "Taser"))
		{
			Buy_Taser( param1 );
		}
		else
		{
			if (bDebug)
			{
				PrintToServer("Client %d selected %s", param1, info);
			}
		}
	}
	else if (action == MenuAction_Cancel)
	{
		g_MenuOpen[param1] = false;
	}
}

// Handle for Grenades menu
public int MenuHandler_Grenades(Handle menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Display) g_MenuOpen[param1] = true;
	else if (action == MenuAction_Select)
	{
		if (PlayerHasTotalNades( param1 ))
		{
			return;
		}
		else
		{
			int client_team = GetClientTeam(param1);
			char info[32];
			GetMenuItem(menu, param2, info, sizeof(info));
			if (StrEqual(info, "HEGrenade"))
			{
				Buy_HEGrenade( param1 );
			}
			if (StrEqual(info, "FBGrenade"))
			{
				Buy_FBGrenade( param1 );
			}
			if (StrEqual(info, "SMGrenade"))
			{
				Buy_SMGrenade( param1 );
			}
			if (StrEqual(info, "DCGrenade"))
			{
				Buy_DCGrenade( param1 );
			}
			if ((view_as<Teams>(client_team) == CS_TEAM_CT) && (StrEqual(info, "IncGrenade")))
			{
				Buy_IncGrenade( param1 );
			}
			if ((view_as<Teams>(client_team) == CS_TEAM_T) && (StrEqual(info, "Molotov")))
			{
				Buy_Molotov( param1 );
			}
			if (StrEqual(info, "TAGrenade"))
			{
				Buy_TAGrenade( param1 );
			}
			else
			{
				if (bDebug)
				{
					PrintToServer("Client %d selected %s", param1, info);
				}
			}
		}
	}
	else if (action == MenuAction_Cancel)
	{
		g_MenuOpen[param1] = false;
	}
}

void CheckCloseHandle(Handle handle)
{
	if (handle != null)
	{
		CloseHandle(handle);
		handle = null;
	}
}

void InitializeMainMenu()
{
	CheckCloseHandle(g_Mainmenu);
	g_Mainmenu = CreateMenu(MenuHandler_Mainmenu, MenuAction_Display|MenuAction_Select|MenuAction_Cancel);
	SetMenuTitle(g_Mainmenu, "Choose category:");
	AddMenuItem(g_Mainmenu, "PistolCat", "Pistols");
	AddMenuItem(g_Mainmenu, "ShotgunCat", "Shotguns");
	AddMenuItem(g_Mainmenu, "SMGCat", "SMGs");
	AddMenuItem(g_Mainmenu, "RifleCat", "Rifles");
	AddMenuItem(g_Mainmenu, "MGCat", "Machineguns");
	AddMenuItem(g_Mainmenu, "EquipmentCat", "Equipment");
	AddMenuItem(g_Mainmenu, "OpenGrenadeMenu", "Grenades");
	SetMenuPagination(g_Mainmenu, MENU_NO_PAGINATION); 
	SetMenuExitButton(g_Mainmenu, true);
}

//Makes proper menu item for display.
void AddBuyMenuItem (Handle menu, char[] menuitem, char[] displayname, int price)
{
	char display[64];
	Format(display, sizeof(display), "%s - %d$", displayname, price);
	AddMenuItem(menu, menuitem, display);
}

void InitializeEquipmentMenu(int client)
{
	CheckCloseHandle(g_Equipmentmenu);
	g_Equipmentmenu = CreateMenu(MenuHandler_Equipment, MenuAction_Display|MenuAction_Select|MenuAction_Cancel);
	int client_team = GetClientTeam(client);
	AddBuyMenuItem(g_Equipmentmenu, "Vest", "Kevlar vest", g_VestPrice);
	AddBuyMenuItem(g_Equipmentmenu, "VestHelmet", "Kevlar vest + Helmet", g_VestHelmetPrice);
	if (GetConVarInt(g_AllowAssaultSuit) == 1)
	{
		AddBuyMenuItem(g_Equipmentmenu, "AssaultSuit", "Heavy Assault Suit", g_ASuitPrice);
	}
	if (view_as<Teams>(client_team) == CS_TEAM_CT)
	{
		AddBuyMenuItem(g_Equipmentmenu, "Defuser", "Defuse/Rescue Kit", g_DefuseKitPrice);
	}
	if ((view_as<Teams>(client_team) == CS_TEAM_CT) && (GetConVarInt(g_AllowShield) == 1))
	{
		AddBuyMenuItem(g_Equipmentmenu, "TacShield", "Tactical Shield", g_ShieldPrice);
	}
	if (GetConVarInt(g_AllowTaser) == 1)
	{
		AddBuyMenuItem(g_Equipmentmenu, "Taser", "Zeus x27", g_TaserPrice);
	}
	if (GetConVarInt(g_AllowHealthshot) == 1)
	{
		AddBuyMenuItem(g_Equipmentmenu, "HealthShot", "Medi-Shot", g_HPShotPrice);
	}
	SetMenuPagination(g_Equipmentmenu, MENU_NO_PAGINATION);
	SetMenuExitButton(g_Equipmentmenu, true);
}

void InitializeGrenadesMenu(int client)
{
	CheckCloseHandle(g_Grenadesmenu);
	g_Grenadesmenu = CreateMenu(MenuHandler_Grenades, MenuAction_Display|MenuAction_Select|MenuAction_Cancel);
	int client_team = GetClientTeam(client);
	AddBuyMenuItem(g_Grenadesmenu, "HEGrenade", "HE Grenade", g_HEPrice);
	AddBuyMenuItem(g_Grenadesmenu, "FBGrenade", "Flashbang", g_FBPrice);
	AddBuyMenuItem(g_Grenadesmenu, "SMGrenade", "Smoke Grenade", g_SGPrice);
	AddBuyMenuItem(g_Grenadesmenu, "DCGrenade", "Decoy Grenade", g_DCPrice);
	if (view_as<Teams>(client_team) == CS_TEAM_CT)
	{
		AddBuyMenuItem(g_Grenadesmenu, "IncGrenade", "Incendiary Grenade", g_IncPrice);
	}
	if (view_as<Teams>(client_team) == CS_TEAM_T)
	{
		AddBuyMenuItem(g_Grenadesmenu, "Molotov", "Molotov", g_MolPrice);
	}
	if (GetConVarInt(g_AllowTAGrenade) == 1)
	{
		AddBuyMenuItem(g_Grenadesmenu, "TAGrenade", "TA Grenade", g_TAGPrice);
	}
	SetMenuPagination(g_Grenadesmenu, MENU_NO_PAGINATION);
	SetMenuExitButton(g_Grenadesmenu, true);
}

public Action Event_HandleSpawn(Handle timer, int user_index)
{
	int client_index = GetClientOfUserId(user_index);
	if ((!client_index) || IsFakeClient(client_index)) return;
	PrintToChat(client_index, "[Buy Menu] Use console command (bind <key> sm_buy) to bind buy menu to any key.");
	PrintToChat(client_index, "[Buy Menu] Unequip all non-standart weapons in inventory or stock items will not spawn.");
	// Timer for setting Heavy armor hands (if you have player model plugin)
	if (GetEntProp(client_index, Prop_Send, "m_bHasHeavyArmor"))
	{
		CreateTimer(0.25, SetHeavyHands, client_index, TIMER_FLAG_NO_MAPCHANGE); 
	}
	// Revert to standart arms (will be overwritten if you have player model plugin)
	/*else
	{
		SetEntPropString(client_index, Prop_Send, "m_szArmsModel", g_PlayerHandsModel[client_index]);
	}*/
	InitializeEquipmentMenu(client_index);
	InitializeGrenadesMenu(client_index);
}

public Action SetHeavyHands(Handle timer, int client_index)
{
	int client_team = GetClientTeam(client_index);
	
	if (view_as<Teams>(client_team) == CS_TEAM_T)
	{
		//SetEntPropString(client_index, Prop_Send, "m_szArmsModel", "models/weapons/t_arms_phoenix_heavy.mdl");
		SetEntPropString(client_index, Prop_Send, "m_szArmsModel", "models/weapons/v_models/arms/phoenix_heavy/v_sleeve_phoenix_heavy.mdl");
		//SetEntityModel(client_index, "models/player/custom_player/legacy/tm_phoenix_heavy.mdl");
	}
	else
	{
		//SetEntPropString(client_index, Prop_Send, "m_szArmsModel", "models/weapons/ct_arms_ctm_heavy.mdl");
		SetEntPropString(client_index, Prop_Send, "m_szArmsModel", "models/weapons/v_models/arms/ctm_heavy/v_sleeve_ctm_heavy.mdl");
		//SetEntityModel(client_index, "models/player/custom_player/legacy/ctm_heavy.mdl");
	}
}

public Action Command_BuyMenu(int client_index, int args)
{
	if (IsPlayerAlive(client_index))
	{
		if (GetEntProp(client_index, Prop_Send, "m_bInBuyZone"))
		{
			if (!g_BuyTimeEnded)
			{
				DisplayMenu(g_Mainmenu, client_index, MENU_TIME_FOREVER);
			}
			else
			{
				EmitSoundToClient(client_index, "ui/weapon_cant_buy.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);
				PrintHintText(client_index, "#SFUI_BuyMenu_YoureOutOfTime");
				return Plugin_Continue;
			}
		}
		else
		{
			EmitSoundToClient(client_index, "ui/weapon_cant_buy.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);
			PrintHintText(client_index, "#SFUI_BuyMenu_NotInBuyZone");
			return Plugin_Continue;
		}
	}
	else PrintHintText(client_index, "You can't use the buy menu while dead.");
	return Plugin_Continue;
}

public Action Show_Submenu(Handle menu, int client_index, int args)
{
	DisplayMenu(menu, client_index, MENU_TIME_FOREVER);
	return Plugin_Continue;
}

public Action Show_EquipMenu(int client_index, int args)
{
	DisplayMenu(g_Equipmentmenu, client_index, MENU_TIME_FOREVER);
	return Plugin_Continue;
}

public Action Show_GrenadeMenu(int client_index, int args)
{
	DisplayMenu(g_Grenadesmenu, client_index, MENU_TIME_FOREVER);
	return Plugin_Continue;
}

stock int CSGO_GetClientArmor(int client)
{
	return GetEntProp(client, Prop_Data, "m_ArmorValue");
}

//Purchase kevlar
public Action Buy_Armor(int client_index)
{
	if (GetEntProp(client_index, Prop_Send, "m_bHasHeavyArmor"))
	{
		PrintHintText(client_index, "You can't replenish Heavy Assault Suit armor with kevlar!");
		EmitSoundToClient(client_index, "ui/weapon_cant_buy.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);
		return;
	}
	if ( CSGO_GetClientArmor(client_index) == 100 )
	{
		PrintHintText(client_index, "#Cstrike_TitlesTXT_Already_Have_Kevlar");
		EmitSoundToClient(client_index, "ui/weapon_cant_buy.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);
		return;
	}
	else
	{
		if (!TakePlayerMoney(client_index, g_VestPrice))
		{
			return;
		}
		SetEntProp(client_index, Prop_Data, "m_ArmorValue", 100);
		EmitSoundToClient(client_index, "survival/armor_pickup_01.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);
	}
}

//Purchase kevlar+helmet
public Action Buy_ArmorHelmet(int client_index)
{
	if (GetEntProp(client_index, Prop_Send, "m_bHasHeavyArmor"))
	{
		PrintHintText(client_index, "You can't replenish Heavy Assault Suit armor with kevlar!");
		EmitSoundToClient(client_index, "ui/weapon_cant_buy.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);
		return;
	}
	if ( CSGO_GetClientArmor(client_index) < 100 )
	{
		//Can't do proper call with function
		if (GetEntProp(client_index, Prop_Send, "m_bHasHelmet"))
		{
			if (!TakePlayerMoney(client_index, g_VestPrice))
			{
				return;
			}
			SetEntProp(client_index, Prop_Data, "m_ArmorValue", 100);
			PrintHintText(client_index, "#Cstrike_TitlesTXT_Already_Have_Helmet_Bought_Kevlar");
			EmitSoundToClient(client_index, "survival/armor_pickup_01.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);
			return;
		}
		else
		{
			if (!TakePlayerMoney(client_index, g_VestHelmetPrice))
			{
				return;
			}
			SetEntProp(client_index, Prop_Data, "m_ArmorValue", 100);
			SetEntProp(client_index, Prop_Send, "m_bHasHelmet", true);
		}
		EmitSoundToClient(client_index, "survival/armor_pickup_01.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);
	}
	else
	{
		//Can't do proper call with function
		if (GetEntProp(client_index, Prop_Send, "m_bHasHelmet"))
		{
			PrintHintText(client_index, "#Cstrike_TitlesTXT_Already_Have_Kevlar_Helmet");
			EmitSoundToClient(client_index, "ui/weapon_cant_buy.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);
			return;
		}
		else
		{
			if (!TakePlayerMoney(client_index, g_HelmetPrice))
			{
				return;
			}
			SetEntProp(client_index, Prop_Send, "m_bHasHelmet", true);
			PrintHintText(client_index, "#Cstrike_TitlesTXT_Already_Have_Kevlar_Bought_Helmet");
			EmitSoundToClient(client_index, "survival/armor_pickup_01.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);
		}
	}
}

//Purchase heavy assault suit
public Action Buy_AssaultSuit(int client_index)
{
	if (g_PlayerPrimary[client_index] != -1)
	{
		char weaponid[64];
		int weapon_index = g_PlayerPrimary[client_index];
		weapon_index = weapon_index+1;
		IntToString(weapon_index, weaponid, sizeof(weaponid));
		KvRewind(WeaponConfigHandle);
		if (!KvJumpToKey(WeaponConfigHandle, weaponid))
		{
			return;
		}
		char weapontype[64];
		KvGetString(WeaponConfigHandle, "weapon_type", weapontype, sizeof(weapontype), "INVALID WEAPON");
		if (bDebug)
		{
			PrintToServer("Client %d's weapon type: %s", client_index, weapontype);
		}
		if (StrEqual("Rifle", weapontype, false))
		{
			PrintHintText(client_index, "#SFUI_BuyMenu_HeavyAssaultSuitRestriction");
			EmitSoundToClient(client_index, "ui/weapon_cant_buy.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);
			return;
		}
	}
	if ((GetEntProp(client_index, Prop_Send, "m_bHasHeavyArmor")) && (CSGO_GetClientArmor(client_index) == GetConVarInt(g_ASuitArmor)))
	{
		PrintHintText(client_index, "You already have Heavy Assault Suit!");
		EmitSoundToClient(client_index, "ui/weapon_cant_buy.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);
		return;
	}
	else
	{
		if (!TakePlayerMoney(client_index, g_ASuitPrice))
		{
			return;
		}
		int client_team = GetClientTeam(client_index);
		SetEntProp(client_index, Prop_Send, "m_bHasHeavyArmor", true);
		SetEntProp(client_index, Prop_Send, "m_bWearingSuit", true);
		SetEntProp(client_index, Prop_Send, "m_bHasHelmet", true);
		SetEntProp(client_index, Prop_Data, "m_ArmorValue", GetConVarInt(g_ASuitArmor));
		GetEntPropString(client_index, Prop_Send, "m_szArmsModel", g_PlayerHandsModel[client_index], sizeof(g_PlayerHandsModel[]));
		if (bDebug)
		{
			PrintToServer("Client %d hands model path: %s", client_index, g_PlayerHandsModel[client_index]);
		}
		if (view_as<Teams>(client_team) == CS_TEAM_T)
		{
			SetEntityModel(client_index, "models/player/custom_player/legacy/tm_phoenix_heavy.mdl");
			//SetEntPropString(client_index, Prop_Send, "m_szArmsModel", "models/weapons/t_arms_phoenix_heavy.mdl");
			SetEntPropString(client_index, Prop_Send, "m_szArmsModel", "models/weapons/v_models/arms/phoenix_heavy/v_sleeve_phoenix_heavy.mdl");
		}
		else
		{
			SetEntityModel(client_index, "models/player/custom_player/legacy/ctm_heavy.mdl");
			//SetEntPropString(client_index, Prop_Send, "m_szArmsModel", "models/weapons/ct_arms_ctm_heavy.mdl");
			SetEntPropString(client_index, Prop_Send, "m_szArmsModel", "models/weapons/v_models/arms/ctm_heavy/v_sleeve_ctm_heavy.mdl");
		}
		EmitSoundToClient(client_index, "survival/armor_pickup_01.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);
	}
}

//Purchase defuse kit
public Action Buy_Defusekit(int client_index)
{
	if (GetEntProp(client_index, Prop_Send, "m_bHasDefuser"))
	{
		PrintHintText(client_index, "You already have the defuse kit!");
		EmitSoundToClient(client_index, "ui/weapon_cant_buy.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);
		return;
	}
	else
	{
		if (!TakePlayerMoney(client_index, g_DefuseKitPrice))
		{
			return;
		}
		SetEntProp(client_index, Prop_Send, "m_bHasDefuser", true);
		EmitSoundToClient(client_index, "items/pickup_quiet_01.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);
	}
}

//Purchase tactical shield
public Action Buy_Shield(int client_index)
{
	if(Client_HasWeapon(client_index, "weapon_shield"))
	{
		PrintHintText(client_index, "You already have ballistic shield!");
		EmitSoundToClient(client_index, "ui/weapon_cant_buy.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);
		return;
	}
	if (!TakePlayerMoney(client_index, g_ShieldPrice))
	{
		return;
	}
	PrintHintText(client_index, "#CSGO_SrvlSpawnEquipAlert_spawn_equip_shield");
	GivePlayerItem(client_index, "weapon_shield");
}

//Check Healthshot limit
bool PlayerHasFullHPShots(int client)
{
	int HPSEquipped = GetClientHPshots(client);
	
	if ((HPShotsAmmo = FindConVar("ammo_item_limit_healthshot")) == null)
	{
		SetFailState("Unable to locate CVar ammo_item_limit_healthshot");
	}
	
	HPShotsLimit = GetConVarInt(HPShotsAmmo);
	
	if ( HPSEquipped >= HPShotsLimit )
	{
		PrintHintText(client, "You can only carry %d Medi-Shots.", HPShotsLimit);
		EmitSoundToClient(client, "ui/weapon_cant_buy.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);
		return true;
	}
	
	return false;
}

//Purchase Healthshot
public Action Buy_Healthshot(int client_index)
{
	if (PlayerHasFullHPShots(client_index))
	{
		return;
	}
	else
	{
		if (!TakePlayerMoney(client_index, g_HPShotPrice))
		{
			return;
		}
		GivePlayerItem(client_index, "weapon_healthshot");
	}
}

//Purchase Taser
public Action Buy_Taser(int client_index)
{
	if(Client_HasWeapon(client_index, "weapon_taser"))
	{
		PrintHintText(client_index, "#Cstrike_TitlesTXT_Cannot_Carry_Anymore");
		EmitSoundToClient(client_index, "ui/weapon_cant_buy.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);
		return;
	}
	else
	{
		if (!TakePlayerMoney(client_index, g_TaserPrice))
		{
			return;
		}
		GivePlayerItem(client_index, "weapon_taser");
	}
}

int GetClientHEGrenades(int client)
{
	return GetEntProp(client, Prop_Data, "m_iAmmo", _, HEGrenadeOffset);
}

int GetClientSmokeGrenades(int client)
{
	return GetEntProp(client, Prop_Data, "m_iAmmo", _, SmokegrenadeOffset);
}

int GetClientFlashbangs(int client)
{
	return GetEntProp(client, Prop_Data, "m_iAmmo", _, FlashbangOffset);
}

int GetClientDecoyGrenades(int client)
{
	return GetEntProp(client, Prop_Data, "m_iAmmo", _, DecoyGrenadeOffset);
}

int GetClientIncendaryGrenades(int client)
{
	return GetEntProp(client, Prop_Data, "m_iAmmo", _, IncenderyGrenadesOffset);
}

int GetClientTAGrenades(int client)
{
	return GetEntProp(client, Prop_Data, "m_iAmmo", _, TAGrenadeOffset);
}

int GetClientHPshots(int client)
{
	return GetEntProp(client, Prop_Data, "m_iAmmo", _, HPShotOffset);
}

//Check total grenade limit
bool PlayerHasTotalNades(int client)
{
	int nadeTotal = GetClientHEGrenades(client) + GetClientFlashbangs(client) + GetClientSmokeGrenades(client) + GetClientDecoyGrenades(client) + GetClientIncendaryGrenades(client) + GetClientTAGrenades(client);
	
	if ((GrenadeAmmoTotal = FindConVar("ammo_grenade_limit_total")) == null)
	{
		SetFailState("Unable to locate CVar ammo_grenade_limit_total");
	}
	
	TotalNades = GetConVarInt(GrenadeAmmoTotal);
	
	if ( nadeTotal >= TotalNades )
	{
		PrintHintText(client, "You can only carry %d grenades total.", TotalNades);
		EmitSoundToClient(client, "ui/weapon_cant_buy.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);
		return true;
	}
	
	return false;
}

//Check flashbang limit
bool PlayerHasFullFBNades(int client)
{
	int FBEquipped = GetClientFlashbangs(client);
	
	if ((GrenadeFBAmmo = FindConVar("ammo_grenade_limit_flashbang")) == null)
	{
		SetFailState("Unable to locate CVar ammo_grenade_limit_flashbang");
	}
	
	FBLimit = GetConVarInt(GrenadeFBAmmo);
	
	if ( FBEquipped >= FBLimit )
	{
		PrintHintText(client, "You can only carry %d flashbangs.", FBLimit);
		EmitSoundToClient(client, "ui/weapon_cant_buy.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);
		return true;
	}
	
	return false;
}

//Check HE grenade limit
bool PlayerHasFullHENades(int client)
{
	int HEEquipped = GetClientHEGrenades(client);
	
	if ((GrenadeAmmo = FindConVar("ammo_grenade_limit_default")) == null)
	{
		SetFailState("Unable to locate CVar ammo_grenade_limit_default");
	}
	GrenadeTypeLimit = GetConVarInt(GrenadeAmmo);
	
	if ( HEEquipped >= GrenadeTypeLimit )
	{
		PrintHintText(client, "You can only carry %d HE grenades.", GrenadeTypeLimit);
		EmitSoundToClient(client, "ui/weapon_cant_buy.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);
		return true;
	}
	
	return false;
}

//Check SG grenade limit
bool PlayerHasFullSGNades(int client)
{
	int SGEquipped = GetClientSmokeGrenades(client);
	
	if ((GrenadeAmmo = FindConVar("ammo_grenade_limit_default")) == null)
	{
		SetFailState("Unable to locate CVar ammo_grenade_limit_default");
	}
	GrenadeTypeLimit = GetConVarInt(GrenadeAmmo);
	
	if ( SGEquipped >= GrenadeTypeLimit )
	{
		PrintHintText(client, "You can only carry %d smoke grenades.", GrenadeTypeLimit);
		EmitSoundToClient(client, "ui/weapon_cant_buy.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);
		return true;
	}
	
	return false;
}

//Check decoy grenade limit
bool PlayerHasFullDCNades(int client)
{
	int DCEquipped = GetClientDecoyGrenades(client);
	
	if ((GrenadeAmmo = FindConVar("ammo_grenade_limit_default")) == null)
	{
		SetFailState("Unable to locate CVar ammo_grenade_limit_default");
	}
	GrenadeTypeLimit = GetConVarInt(GrenadeAmmo);
	
	if ( DCEquipped >= GrenadeTypeLimit )
	{
		PrintHintText(client, "You can only carry %d decoy grenades.", GrenadeTypeLimit);
		EmitSoundToClient(client, "ui/weapon_cant_buy.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);
		return true;
	}
	
	return false;
}

//Check incendaries limit
bool PlayerHasFullIncNades(int client)
{
	int IncEquipped = GetClientIncendaryGrenades(client);
	
	if ((GrenadeAmmo = FindConVar("ammo_grenade_limit_default")) == null)
	{
		SetFailState("Unable to locate CVar ammo_grenade_limit_default");
	}
	GrenadeTypeLimit = GetConVarInt(GrenadeAmmo);
	
	if ( IncEquipped >= GrenadeTypeLimit )
	{
		PrintHintText(client, "You can only carry %d incendary grenades/molotovs.", GrenadeTypeLimit);
		EmitSoundToClient(client, "ui/weapon_cant_buy.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);
		return true;
	}
	
	return false;
}

//Check TA grenade limit
bool PlayerHasFullTANades(int client)
{
	int TAEquipped = GetClientTAGrenades(client);
	
	if ((GrenadeAmmo = FindConVar("ammo_grenade_limit_default")) == null)
	{
		SetFailState("Unable to locate CVar ammo_grenade_limit_default");
	}
	GrenadeTypeLimit = GetConVarInt(GrenadeAmmo);
	
	if ( TAEquipped >= GrenadeTypeLimit )
	{
		PrintHintText(client, "You can only carry %d tactical awareness grenades.", GrenadeTypeLimit);
		EmitSoundToClient(client, "ui/weapon_cant_buy.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);
		return true;
	}
	
	return false;
}

public Action Buy_HEGrenade(int client_index)
{
	if (PlayerHasFullHENades(client_index))
	{
		return;
	}
	if (!TakePlayerMoney(client_index, g_HEPrice))
	{
		return;
	}
	GivePlayerItem(client_index, "weapon_hegrenade");
}

public Action Buy_FBGrenade(int client_index)
{
	if (PlayerHasFullFBNades(client_index))
	{
		return;
	}
	if (!TakePlayerMoney(client_index, g_FBPrice))
	{
		return;
	}
	GivePlayerItem(client_index, "weapon_flashbang");
}

public Action Buy_SMGrenade(int client_index)
{
	if (PlayerHasFullSGNades(client_index))
	{
		return;
	}
	if (!TakePlayerMoney(client_index, g_SGPrice))
	{
		return;
	}
	GivePlayerItem(client_index, "weapon_smokegrenade");
}

public Action Buy_DCGrenade(int client_index)
{
	if (PlayerHasFullDCNades(client_index))
	{
		return;
	}
	if (!TakePlayerMoney(client_index, g_DCPrice))
	{
		return;
	}
	GivePlayerItem(client_index, "weapon_decoy");
}

public Action Buy_Molotov(int client_index)
{
	if (PlayerHasFullIncNades(client_index))
	{
		return;
	}
	if (!TakePlayerMoney(client_index, g_MolPrice))
	{
		return;
	}
	GivePlayerItem(client_index, "weapon_molotov");
}

public Action Buy_IncGrenade(int client_index)
{
	if (PlayerHasFullIncNades(client_index))
	{
		return;
	}
	if (!TakePlayerMoney(client_index, g_IncPrice))
	{
		return;
	}
	GivePlayerItem(client_index, "weapon_incgrenade");
}

public Action Buy_TAGrenade(int client_index)
{
	if (PlayerHasFullTANades(client_index))
	{
		return;
	}
	if (!TakePlayerMoney(client_index, g_TAGPrice))
	{
		return;
	}
	GivePlayerItem(client_index, "weapon_tagrenade");
}

bool TakePlayerMoney(int client_index, int amount)
{
    int money = GetEntData(client_index, m_MoneyAmount);
    
    money -= amount;
    if (money < 0)
    {
		PrintHintText(client_index, "#Cstrike_TitlesTXT_Not_Enough_Money");
		EmitSoundToClient(client_index, "ui/weapon_cant_buy.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);
		return false;
    }
    
    SetEntData(client_index, m_MoneyAmount, money, 4, true);
    return true;
}
