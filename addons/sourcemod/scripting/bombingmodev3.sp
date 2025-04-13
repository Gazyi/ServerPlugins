/*
NEED TO FIND OUT AND FIX:
[Critical]
1. Sometimes killing planted_c4 entity makes invisible other planted_c4. (Maybe it hides model after explosion?)
[Additional]
2. Block bots from dropping C4 on player "+use". (Done with DHooks)
3. Make UI round timer corresponds properly. (Everything here is client-side only, except there's way to fool clients thinking that is coop mode and set timer manually every second.)
4. Fix CT bot stop moving after bomb explosion.
5. Fix CT bots trying to defuse bomb at bombsite that was already defused.
6. Fix T bots trying to plant bomb on already exploded bombsite.
5. Find a way to get proper func_bomb_target position when it's origin is shifted. (e.g. de_airstrip: https://steamcommunity.com/sharedfiles/filedetails/?id=126970036)
6. Combine multiple bombsites into one if they're close enough. (e.g. )

Note: Rewards won't work properly with round backups and will reset on new non-halftime round (base config now disables round backups).
*/
#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <cstrike>
#include <dhooks>

//=== Plugin ConVar handles ===//
Handle bm_enabled;
Handle bm_debug;
Handle bm_onlycustomgametype;
Handle bm_gamemode;
Handle bm_lastround;

//=== Debug mode ===//
bool bDebug = true;

//=== Existing ConVars handles ===//
Handle srv_gametype;
Handle srv_gamemode;
Handle ct_reward_defused;
Handle t_reward_exploded;
Handle t_bonus_defused;
Handle team_loser_bonus;
Handle maxmoney;

//=== ConVars cache ===//
bool bModeEnabled = false;
bool bOnlyCustomGameType = false;
int iCustomGameMode = 0;
bool bMaxMoneyLastRound = false;
int iRewardTExploded = 0;
int iRewardCTDefused = 0;
int iRewardTDefused = 0;
int iRewardTeamLoser = 0;
int iMaxMoney = 0;

//=== Round handles and vars ===//
Handle RoundDelayRestart;
Handle RoundTime;
Handle RoundTimeHUD;
Handle roundtimer = INVALID_HANDLE;
bool bEndingRound = false;
bool bRoundTimerStop = false;
int iRoundTime = 9999;

//=== Map vars and handles ===//
bool bFoundSiteNames = false;
int BombsiteIndex[4] = {INVALID_ENT_REFERENCE, ...};
int BombsiteName[4] = {-1, ...}; // Bombsite indexes for names - 0 is A, 1 is B, etc.
int BombsitePlanted[4] = {-1, ...}; // Stores planted_c4 IDs
int BombsiteExploded[4] = {0, ...};
int BombsitesCount = 0;
int BombsitesCountExploded = 0;

//=== Player vars and handles ===//
int PlayerBombsiteID[MAXPLAYERS + 1] = {-1, ...};

//=== Bot support ===//
Handle g_FindUseEntity = INVALID_HANDLE;
Handle hGetClosestZone = INVALID_HANDLE;

//=== Config paths ===//
#define CONFIG_DIR "sourcemod/bombingmode/"
char baseConfigPath[PLATFORM_MAX_PATH];
char mapname[PLATFORM_MAX_PATH];
char mapConfigPath[PLATFORM_MAX_PATH];

public Plugin myinfo =
{
	name = "Bombing Mode",
	description = "Crappy copy of MW2 demolition gamemode",
	author = "Gazyi",
	version = "0.2.6"
};

public void OnPluginStart()
{
    // Player events hooks
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_hurt", Event_PlayerHurt);
    // Bomb events hooks
    HookEvent("bomb_planted", Event_BombPlanted);
    HookEvent("bomb_defused", Event_BombDefused);
    HookEvent("bomb_exploded", Event_BombExploded);
    // Round events hooks
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("round_freeze_end", Event_RoundFreezeEnd, EventHookMode_PostNoCopy);
    HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
    HookEvent("round_announce_final", Event_RoundFinal, EventHookMode_PostNoCopy);

    // Round timer handles
    RoundDelayRestart = FindConVar("mp_round_restart_delay");
    RoundTime = FindConVar("mp_roundtime_defuse");
    RoundTimeHUD = CreateHudSynchronizer();

    // Cache reward handles
    t_reward_exploded = FindConVar("cash_team_terrorist_win_bomb");
    t_bonus_defused = FindConVar("cash_team_planted_bomb_but_defused");
    ct_reward_defused = FindConVar("cash_team_win_by_defusing_bomb");
    team_loser_bonus = FindConVar("cash_team_loser_bonus");
    maxmoney = FindConVar("mp_maxmoney");

    // Plugin CVar handles
    bm_enabled = CreateConVar("sm_bm_enabled", "1", "Enable Bombing Mode.\n0 = Disabled\n1 = Enabled", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    bm_debug = CreateConVar("sm_bm_debug", "1", "Debug Mode.\n0 = Disabled\n1 = Enabled", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    bm_onlycustomgametype = CreateConVar("sm_bm_onlycustom", "1", "Allows Bombing Mode only if Game Type is set to Custom. Requires map reload.\n0 = Disabled\n1 = Enabled", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    bm_gamemode = CreateConVar("sm_bm_gamemode", "0", "If set to Custom only, allows Bombing Mode only if Game Mode is set to this number. Requires map reload.");
    bm_lastround = CreateConVar("sm_bm_maxmoney_last_round", "1", "Gives all players max amount of money at last round in match without match points.\n0 = Disabled\n1 = Enabled", FCVAR_NOTIFY, true, 0.0, true, 1.0);

    // ConVar changes hooks
    HookConVarChange(t_reward_exploded, CvarChanged);
    HookConVarChange(t_bonus_defused, CvarChanged);
    HookConVarChange(ct_reward_defused, CvarChanged);
    HookConVarChange(team_loser_bonus, CvarChanged);
    HookConVarChange(maxmoney, CvarChanged);
    HookConVarChange(bm_enabled, CvarChanged);
    HookConVarChange(bm_debug, CvarChanged);
    HookConVarChange(bm_onlycustomgametype, CvarChanged);
    HookConVarChange(bm_gamemode, CvarChanged);
    HookConVarChange(bm_lastround, CvarChanged);
    CacheCvars();

    // Init blocking hook.
    InitFindEntity();

    // Player hooking
    for ( int i = 1; i <= MaxClients; i++ )
    {
        if(IsClientInGame(i)) OnClientPutInServer(i);
    }
}

//=== CVar changes and caches ===//
public void CvarChanged(Handle cvar, const char[] oldvalue, const char[] newvalue)
{
	if (cvar == bm_enabled)
	{
		bModeEnabled = GetConVarBool(bm_enabled);
		if (!bModeEnabled)
		{
			delete roundtimer;
		}
	}
	if (cvar == bm_debug)
		bDebug = GetConVarBool(bm_debug);
	if (cvar == bm_onlycustomgametype)
		bOnlyCustomGameType = GetConVarBool(bm_onlycustomgametype);
	if (cvar == bm_gamemode)
		iCustomGameMode = GetConVarInt(bm_gamemode);
	if (cvar == bm_lastround)
		bMaxMoneyLastRound = GetConVarBool(bm_lastround);
	if (cvar == t_reward_exploded)
		iRewardTExploded = GetConVarInt(t_reward_exploded);
	if (cvar == ct_reward_defused)
		iRewardCTDefused = GetConVarInt(ct_reward_defused);
	if (cvar == t_bonus_defused)
		iRewardTDefused = GetConVarInt(t_bonus_defused);
	if (cvar == team_loser_bonus)
		iRewardTeamLoser = GetConVarInt(team_loser_bonus);
	if (cvar == maxmoney)
		iMaxMoney = GetConVarInt(maxmoney);
}

public void CacheCvars()
{
	bModeEnabled = GetConVarBool(bm_enabled);
	bDebug = GetConVarBool(bm_debug);
	bOnlyCustomGameType = GetConVarBool(bm_onlycustomgametype);
	iCustomGameMode = GetConVarInt(bm_gamemode);
	bMaxMoneyLastRound = GetConVarBool(bm_lastround);
	
	iRewardTExploded = GetConVarInt(t_reward_exploded);
	iRewardCTDefused = GetConVarInt(ct_reward_defused);
	iRewardTDefused = GetConVarInt(t_bonus_defused);
	iRewardTeamLoser = GetConVarInt(team_loser_bonus);
	iMaxMoney = GetConVarInt(maxmoney);
}
//==========//

//=== Config functions ===//
// Apply gamemode config after all other configs.
public void OnAutoConfigsBuffered()
{
	// So, we are on map that has bomb targets and gamemode is enabled.
	if (bModeEnabled && FindEntityByClassname(-1, "func_bomb_target") != -1)
	{
		// We need additional check if we can apply game mode only to custom game type
		if (bOnlyCustomGameType)
		{
			if ((srv_gametype = FindConVar("game_type")) == null)
			{
				SetFailState("Unable to get Game Type.");
			}
			int server_gametype = GetConVarInt(srv_gametype);
			
			if ((srv_gamemode = FindConVar("game_mode")) == null)
			{
				SetFailState("Unable to get Game Mode.");
			}
			int server_gamemode = GetConVarInt(srv_gamemode);
			
			if ((server_gametype == 3) && (iCustomGameMode == server_gamemode))
			{
				ExecuteBMConfigs();
			}
			else
			{
				SetFailState("Incorrect Game Type or Game Mode, Bombing Mode is disabled.");
			}
		}
		// Otherwise, just run it if it's not set.
		else
		{
			ExecuteBMConfigs();
		}
	}
	else
	{
		SetFailState("Bombing Mode is disabled.");
	}
}

public void ExecuteBMConfigs()
{
	//Load base config, let's pretend that there's no map named like that.
	char cfgdir[PLATFORM_MAX_PATH];
	Format(cfgdir, sizeof(cfgdir), "cfg/%s", CONFIG_DIR);
	Handle dir = OpenDirectory(cfgdir);
	if (dir == INVALID_HANDLE) 
	{
		SetFailState("Error iterating folder %s, folder doesn't exist!", cfgdir);
		return;
	}
	strcopy(baseConfigPath, sizeof(baseConfigPath), CONFIG_DIR);
	StrCat(baseConfigPath, PLATFORM_MAX_PATH, "base");
	LogMessage("[Bombing Mode] Executing base parameters: %s", baseConfigPath);
	// Get standart parameters are from casual gamemode configs, then overwrite them with our gamemode.
	ServerCommand("exec gamemode_casual");
	ServerCommand("exec gamemode_casual_server");
	ServerCommand("exec %s", baseConfigPath);
	//Now, check this folder for map specific config
	GetCurrentMap(mapname, sizeof(mapname));
	//Workshop maps fix (by tabakhase)
	int mapSepPos = FindCharInString(mapname, '/', true);
	if (mapSepPos != -1) 
	{
		strcopy(mapname, sizeof(mapname), mapname[mapSepPos+1]);
	}
	strcopy(mapConfigPath, sizeof(mapConfigPath), CONFIG_DIR);
	StrCat(mapConfigPath, PLATFORM_MAX_PATH, mapname);
	LogMessage("[Bombing Mode] Executing map specific parameters: %s", mapConfigPath);
	ServerCommand("exec %s", mapConfigPath);
	CloseHandle(dir);
	//Restart game to apply convar changes
	BombsitesCount = 0;
	FindBombTargets();
	bModeEnabled = true;
	ServerCommand("mp_restartgame 1");
}
//==========//

//=== Bot functions ===//
void PrepSDKCalls()
{
	GameData gConf = LoadGameConfigFile("bombingmode.games");
	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(gConf, SDKConf_Signature, "CCSBotManagerGetClosestZone");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
  	hGetClosestZone = EndPrepSDKCall();
}
//==========//

//=== Player functions ===//
// Blocking +use on bots to stop them dropping C4. (Based on https://gist.github.com/CookStar/d7577b454f256445e3b64fcaf1d189da , because SDKHook_Use can't stop it.)
void InitFindEntity()
{
    GameData gConf = LoadGameConfigFile("bombingmode.games");

    if (!gConf)
    {
        SetFailState("Failed to load Bombing Mode gamedata!!!");
    }

    //virtual CBaseEntity *CCSPlayer::FindUseEntity( void )
    int offset = GameConfGetOffset(gConf, "FindUseEntity");
    if (offset == -1)
    {
        SetFailState("Failed to load offset for CCSPlayer::FindUseEntity!!!");
    }

    g_FindUseEntity = DHookCreate(offset, HookType_Entity, ReturnType_CBaseEntity, ThisPointer_CBaseEntity, Detour_FindUseEntity);
    if (!g_FindUseEntity)
    {
        SetFailState("Failed to create detour CCSPlayer::FindUseEntity!!!");
    }
    LogMessage("[Bombing Mode] Hooked CCSPlayer::FindUseEntity!");

    delete gConf;
}

MRESReturn Detour_FindUseEntity(int client, Handle hReturn)
{
	if (IsValidPlayer(client) && !IsFakeClient(client))
	{
		int entity = DHookGetReturn(hReturn);
		if (IsValidPlayer(entity) && IsFakeClient(entity))
		{
			LogMessage("[Bombing Mode] Client %i called +use on entity ID: %i, which is bot.", client, entity);
			DHookSetReturn(hReturn, 0);
			return MRES_Supercede;// Ignore +use on bots.
		}
	}
	return MRES_Ignored;
}

public void OnClientPutInServer(int client_index)
{
	if (!IsFakeClient(client_index))
	{
		DHookEntity(g_FindUseEntity, true, client_index);
	}
	FindBombsiteIndexes();
}

stock bool IsValidPlayer(int client)
{
	if(client <= 0 || client > MaxClients)
		return false;
		
	return IsClientInGame(client);
}

public void OnClientDisconnect(int client_index)
{
	// Clear dropped bombs
	int droppedc4 = -1;
	
	while ((droppedc4 = FindEntityByClassname(droppedc4, "weapon_c4")) != -1) 
	{
		int state = GetEntProp(droppedc4, Prop_Send, "m_iState");
		if (bDebug) LogMessage("weapon_c4 state: %i", state);
		if ( state == 0 )
		{
			AcceptEntityInput(droppedc4, "Kill");
		}
	}
}

public Action Event_PlayerSpawn(Handle event, const char[] name, bool dontBroadcast)
{
    if (bModeEnabled && !(GameRules_GetProp("m_bWarmupPeriod")))
    {
        CreateTimer(0.1, Event_HandleSpawn, GetEventInt(event, "userid"));
    }
    return Plugin_Continue;
}

// Give All Ts C4 on spawn
public Action Event_HandleSpawn(Handle timer, int user_index)
{
	int client_index = GetClientOfUserId(user_index);
	if (!client_index) return Plugin_Handled;
	PlayerBombsiteID[client_index] = -1;
	if (GetClientTeam(client_index) == CS_TEAM_T)
	{
		RequestFrame(GiveC4ToPlayer, client_index);
	}
	return Plugin_Continue;
}

public Action Event_GiveC4ToPlayer(Handle timer, int client_index)
{
	GiveC4ToPlayer(client_index);
	return Plugin_Handled;
}

public void GiveC4ToPlayer(int client_index)
{
	if (IsPlayerAlive(client_index)) GivePlayerItem(client_index, "weapon_c4");
}

//"player_death" doesn't detect C4 in inventory, because it's dropped already.
public Action Event_PlayerHurt(Handle event, const char[] name, bool dontBroadcast)
{
	int client_index = GetClientOfUserId(GetEventInt(event, "userid"));
	int healthRemaining = GetEventInt(event, "health");
	
	if (GetClientTeam(client_index) == CS_TEAM_T && healthRemaining <= 0)
	{
		int c4entity = GetPlayerWeaponSlot(client_index, CS_SLOT_C4);
		if (bDebug) LogMessage("%L was killed, they %s", client_index, (c4entity == -1 ? "do not have C4." : "do have C4, removing it."));
		
		if (c4entity != INVALID_ENT_REFERENCE)
		{
			RemovePlayerItem(client_index, c4entity);
		}
	}
	return Plugin_Continue;
}

// Show reward chat message to team.
stock void RewardTeam(int team, int award, const char[] reason)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if(IsClientInGame(client) && GetClientTeam(client) == team)
		{
			int client_money = GetEntProp(client, Prop_Send, "m_iAccount");
			if (bDebug) LogMessage("[Bombing Mode] Client %i m_iAccount: $%i", client, client_money);
			client_money = client_money + award;
			// It needs to be limited by mp_maxmoney
			if (client_money > iMaxMoney)
			{
				client_money = iMaxMoney;
			}
			if (bDebug) LogMessage("[Bombing Mode] Client %i new account: $%i", client, client_money);
			SetEntProp(client, Prop_Send, "m_iAccount", client_money);
			
			SetGlobalTransTarget(client);
			char szBuffer[256];
			Format(szBuffer, sizeof(szBuffer), "\x06 +$%i\x01: %s", award, reason);
			VFormat(szBuffer, sizeof(szBuffer), szBuffer, 3);
			
			PrintToChat(client, " %s", szBuffer);
		}
	}
}

// Show message in chat about plant/defuse/explode.
public void BombsiteMessage(int PlantIndex, int event)
{
	char sitename[2];
	
	// PlantIndex is a number of element in BombsiteIndex array
	if (BombsiteName[PlantIndex] == 0) sitename = "A";
	if (BombsiteName[PlantIndex] == 1) sitename = "B";
	if (BombsiteName[PlantIndex] == 2) sitename = "C";
	if (BombsiteName[PlantIndex] == 3) sitename = "D";
	
	if (event == 0) // Planted
	{
		PrintToChatAll("\x01[Bombing Mode] Bomb has been\x02 planted\x01 - Bombsite\x06 %s.", sitename);
		return;
	}
	if (event == 1) // Defused
	{
		PrintToChatAll("\x01[Bombing Mode] Bomb has been\x04 defused\x01 - Bombsite\x06 %s.", sitename);
		return;
	}
	if (event == 2) // Exploded
	{
		PrintToChatAll("\x01[Bombing Mode] Bomb has been\x09 exploded\x01 - Bombsite\x06 %s. Bonus time added.", sitename);
		return;
	}
}
//==========//

//=== Round functions ===//
public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	BombsitePlanted = {-1, -1, -1 ,-1};
	BombsiteExploded = {0, 0, 0 ,0};
	BombsitesCountExploded = 0;
	if (bDebug)
	{
		LogMessage("[Bombing Mode] Reseting values...");
		LogMessage("[Bombing Mode] BombsitePlanted: %i, %i, %i, %i", BombsitePlanted[0], BombsitePlanted[1], BombsitePlanted[2], BombsitePlanted[3]);
		LogMessage("[Bombing Mode] BombsiteExploded: %i, %i, %i, %i", BombsiteExploded[0], BombsiteExploded[1], BombsiteExploded[2], BombsiteExploded[3]);
		LogMessage("[Bombing Mode] BombsitesCountExploded: %i", BombsitesCountExploded);
	}
	bEndingRound = false;
	if (roundtimer != INVALID_HANDLE) delete roundtimer;
	if (!GameRules_GetProp("m_bWarmupPeriod"))
	{
		bRoundTimerStop = false;
		for (int client_index = 1; client_index <= MaxClients; client_index++)
		{
			if (client_index && IsClientInGame(client_index))
			{ 
				if (GetClientTeam(client_index) == CS_TEAM_T)
				{
					PrintToChat(client_index, " \x01\x06Bombing Mode. Destroy both objectives to win!");
				}
				else if (GetClientTeam(client_index) == CS_TEAM_CT)
				{
					PrintToChat(client_index, " \x01\x06Bombing Mode. Defend objectives until round time ends!");
				}	
			}
		}
	}
}

// mp_ignore_round_win_conditions blocks wins by round end too, so we need a fucking round timer.
public void Event_RoundFreezeEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (!GameRules_GetProp("m_bWarmupPeriod"))
	{
		iRoundTime = RoundToZero(GetConVarFloat(RoundTime) * 60);
		roundtimer = CreateTimer(1.0, Timer_Round, _, TIMER_REPEAT);
	}
}

// Give max money at start of the final round.
public void Event_RoundFinal(Event event, const char[] name, bool dontBroadcast)
{
	if (bModeEnabled && bMaxMoneyLastRound)
	{
		for (int client = 1; client <= MaxClients; client++)
		{
			if (client && IsClientInGame(client))
			{
				SetEntProp(client, Prop_Send, "m_iAccount", iMaxMoney);
			}
		}
	}
}

public Action Timer_Round(Handle hTimer)
{
	if (!bRoundTimerStop)
	{
		iRoundTime--;
	}
	if(iRoundTime <= 0)
	{
		RequestFrame(Event_RoundEndWin);
		return Plugin_Handled;
	}
	if (RoundTimeHUD != INVALID_HANDLE)
	{
		SetHudTextParams(0.48, 0.07, 0.2, 255, 255, 255, 255, _, _, 0.0, 0.0);
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i))
			{
				if(!IsFakeClient(i))
				{
					if (!bRoundTimerStop)
					{
						ShowSyncHudText(i, RoundTimeHUD, "%02d:%02d", iRoundTime / 60, iRoundTime % 60);
					}
					else
					{
						SetHudTextParams(0.45, 0.07, 0.2, 255, 0, 0, 255, _, _, 0.0, 0.0);
						ShowSyncHudText(i, RoundTimeHUD, "Bomb Planted!");
					}
				}
			}
		}
	}
	return Plugin_Continue;
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (roundtimer != INVALID_HANDLE)
	{
		delete roundtimer;
	}
}

public void OnMapEnd() // required, because forcible change level doesn't fire "round_end" event
{
    if (roundtimer != INVALID_HANDLE)
	{
		delete roundtimer;
	}
}

public void Event_RoundEndWin()
{
	if (!bEndingRound)
	{
		//PrintToChatAll("[Bombing Mode] Round Time ended, sending CT Win event...");
		if (bDebug) LogMessage("[Bombing Mode] Round Time ended, sending CT Win event...");
		
		int iEntGameEnd = -1;
		iEntGameEnd = FindEntityByClassname(iEntGameEnd, "game_round_end");
		
		if (iEntGameEnd < 1)
		{
			iEntGameEnd = CreateEntityByName("game_round_end");
			if (IsValidEntity(iEntGameEnd)) 
			{
				if (bDebug) LogMessage("[Bombing Mode] Can't find game_round_end entity, creating a new one.");
				DispatchSpawn(iEntGameEnd);
			}
			else
			{
				LogMessage("[Bombing Mode] Unable to find or create a game_round_end entity.");
				return;
			}
		}
		
		if (roundtimer != INVALID_HANDLE)
		{
			delete roundtimer;
		}
		float flRoundDelay = GetConVarFloat(RoundDelayRestart);
		SetVariantFloat(flRoundDelay);
		AcceptEntityInput(iEntGameEnd, "EndRound_CounterTerroristsWin");
		bEndingRound = true;
	}
}
//==========//

//=== Bombsite functions ===//
public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrEqual(classname, "func_bomb_target", false))
	{
		SDKHookEx(entity, SDKHook_StartTouchPost, Bombsite_StartTouchPost);
		SDKHookEx(entity, SDKHook_TouchPost, Bombsite_TouchPost);
		SDKHookEx(entity, SDKHook_EndTouchPost, Bombsite_EndTouchPost);
	}
	if(StrEqual(classname, "planted_c4", false))
	{
		SDKHookEx(entity, SDKHook_SpawnPost, PlantedC4_SpawnPost);
	}
}

public void FindBombsiteIndexes()
{
	// Thanks to exvel - http://forums.alliedmods.net/showthread.php?p=1287116
	// Get bombsite name (Only vectors for A and B exists)
	// This doesn't work with func_bomb_target that has custom origin point.
	if (!bFoundSiteNames)
	{
		int entindex = -1;
		LogMessage("[Bombing Mode] Searching for bombsite names...");
		float vecBombsiteCenterA[3];
		float vecBombsiteCenterB[3];
		
		entindex = FindEntityByClassname(entindex, "cs_player_manager");
		if (IsValidEntity(entindex)) 
		{
			GetEntPropVector(entindex, Prop_Send, "m_bombsiteCenterA", vecBombsiteCenterA);
			GetEntPropVector(entindex, Prop_Send, "m_bombsiteCenterB", vecBombsiteCenterB);
		} 
		else 
		{
			LogError("Failed to find cs_player_manager");
			return;
		}
		if (bDebug) LogMessage("m_bombsiteCenterA origin: [ %f, %f, %f ]", vecBombsiteCenterA[0], vecBombsiteCenterA[1], vecBombsiteCenterA[2]);
		if (bDebug) LogMessage("m_bombsiteCenterB origin: [ %f, %f, %f ]", vecBombsiteCenterB[0], vecBombsiteCenterB[1], vecBombsiteCenterB[2]);
		
		float vecBombsiteMin[3];
		float vecBombsiteMax[3];
		int bombsites = 0;
		
		for ( int i = 0; i <= 3; i++ )
		{
			if (BombsiteIndex[i] != -1)
			{
				GetEntPropVector(BombsiteIndex[i], Prop_Send, "m_vecMins", vecBombsiteMin);
				GetEntPropVector(BombsiteIndex[i], Prop_Send, "m_vecMaxs", vecBombsiteMax);
				if (bDebug) LogMessage("Bombsite ID: %i", BombsiteIndex[i]);
				if (bDebug) LogMessage("Min: [ %f, %f, %f ]", vecBombsiteMin[0], vecBombsiteMin[1], vecBombsiteMin[2]);
				if (bDebug) LogMessage("Max: [ %f, %f, %f ]", vecBombsiteMax[0], vecBombsiteMax[1], vecBombsiteMax[2]);
				
				if (IsVecBetween(vecBombsiteCenterA, vecBombsiteMin, vecBombsiteMax))
				{
					BombsiteName[i] = 0;
					LogMessage("[Bombing Mode] Bombsite A have EntityID %i", BombsiteIndex[i]);
					bombsites++;
					LogMessage("[Bombing Mode] Bombsites: %i", bombsites);
				}
				else if ((IsVecBetween(vecBombsiteCenterB, vecBombsiteMin, vecBombsiteMax)) || bombsites == 1)
				{
					BombsiteName[i] = 1;
					LogMessage("[Bombing Mode] Bombsite B have EntityID %i", BombsiteIndex[i]);
					bombsites++;
					LogMessage("[Bombing Mode] Bombsites: %i", bombsites);
				}
				// Other indexes depend on entity ID.
				else
				{
					if (bombsites == 0)
					{
						BombsiteName[i] = 0;
						LogMessage("[Bombing Mode] Bombsite A have EntityID %i", BombsiteIndex[i]);
						bombsites++;
						LogMessage("[Bombing Mode] Bombsites: %i", bombsites);
					}
					else if (bombsites == 2)
					{
						BombsiteName[i] = 2;
						LogMessage("[Bombing Mode] Bombsite C have EntityID %i", BombsiteIndex[i]);
						bombsites++;
						LogMessage("[Bombing Mode] Bombsites: %i", bombsites);
					}
					else 
					{
						BombsiteName[i] = 3;
						LogMessage("[Bombing Mode] Bombsite D have EntityID %i", BombsiteIndex[i]);
						LogMessage("[Bombing Mode] Bombsites: %i", bombsites);
					}
				}
			}
		}
		bFoundSiteNames = true;
	}
}

public void FindBombTargets()
{
	//It's usually 2, but sometimes there's 3 and even 4 bombsites.
	int i = INVALID_ENT_REFERENCE;
	int j = 0;
	while ((i = FindEntityByClassname(i, "func_bomb_target")) != -1)
	{
		if (i < 0 || !IsValidEntity(i))	continue;
		
		char classname[65];
		GetEntityClassname(i, classname, sizeof(classname));
		if(StrEqual(classname, "func_bomb_target", false))
		{
			BombsiteIndex[j] = i;
			LogMessage("[Bombing Mode] Found bombsite with EntityID %i", BombsiteIndex[j]);
			BombsitesCount++;
			LogMessage("[Bombing Mode] BombsitesCount: %i", BombsitesCount);
			j++;
		}
	}
	bFoundSiteNames = false;
}

public void Bombsite_StartTouchPost(int entity, int other)
{
	if (bModeEnabled)
	{
		if(other > 0 && other <= MaxClients)
		{
			if (bDebug) LogMessage("Client %i moved in bomb site with ID %i", other, entity);
			//PrintToChatAll("Client %i moved in bomb site with ID %i", other, entity);
			PlayerBombsiteID[other] = entity;
			for ( int i = 0; i <= 3; i++ )
			{
				if (BombsiteIndex[i] == entity)
				{
					if (bDebug) LogMessage("Entity ID: %i, Planted = %i, Exploded = %i", BombsiteIndex[i], BombsitePlanted[i], BombsiteExploded[i]);
					//PrintToChatAll("Entity ID: %i, Planted = %i, Exploded = %i", BombsiteIndex[i], BombsitePlanted[i], BombsiteExploded[i]);
					return;
				}
			}
		}
	}
}

// Overwrite func_bomb_target to be plantable again in same round after successful defuse.
public void Bombsite_TouchPost(int entity, int other)
{
	if (bModeEnabled)
	{
		if(other > 0 && other <= MaxClients)
		{
			for ( int i = 0; i <= 3; i++ )
			{ 
				if (BombsiteIndex[i] == entity)
				{
					if ((GetClientTeam(other) == CS_TEAM_T) && (BombsitePlanted[i] == -1) && (BombsiteExploded[i] == 0))
					{
						SetEntProp(other, Prop_Send, "m_bInBombZone", 1);
						return;
					}
					// Fix for plant site reset after another bombsite was exploded/defused.
					else
					{
						SetEntProp(other, Prop_Send, "m_bInBombZone", 0);
						return;
					}
				}
			}
		}
	}
}

// Overwrite func_bomb_target to be plantable again in same round after successful defuse.
public void Bombsite_EndTouchPost(int entity, int other)
{
	if (bModeEnabled)
	{
		if(other > 0 && other <= MaxClients)
		{
			if (bDebug) LogMessage("Client %i moved out of bomb site with ID %i", other, entity);
			//PrintToChatAll("Client %i moved out of bomb site with ID %i", other, entity);
			PlayerBombsiteID[other] = -1;
			return;
		}
	}
}
//==========//

//=== Planted bomb functions ===//
public void PlantedC4_SpawnPost(int entity)
{
	if (bModeEnabled)
	{
		if (entity == -1)
		{
			LogError("Spawned C4 has incorrect ID.");
			if (bDebug) PrintToChatAll("Spawned C4 has incorrect ID.");
			return;
		}
		
		float c4origin[3];
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", c4origin);
		if (bDebug) LogMessage("C4 spawned. ID: %i, Origin: [ %f, %f, %f ]", entity, c4origin[0], c4origin[1], c4origin[2]);
		//PrintToChatAll("C4 spawned. ID: %i, Origin: [ %f, %f, %f ]", entity, c4origin[0], c4origin[1], c4origin[2]);
		
		int ticking = GetEntProp(entity, Prop_Send, "m_bBombTicking");
		if (ticking == 0)
		{
			LogMessage("Spawned C4 is not primed.");
			return;
		}
		
		float vecBombsiteMin[3];
		float vecBombsiteMax[3];
		for ( int i = 0; i <= 3; i++ )
		{
			if (bDebug) LogMessage("Bombsite ID: %i", BombsiteIndex[i]);
			// Player can touch border of func_bomb_target and plant bomb. That causes planted_c4 spawn outside of trigger.
			// Substract/Add player hull size (32 units) from vecMin / to vecMax to compesate that.
			GetEntPropVector(BombsiteIndex[i], Prop_Send, "m_vecMins", vecBombsiteMin);
			if (bDebug) LogMessage("Min: [ %f, %f, %f ]", vecBombsiteMin[0], vecBombsiteMin[1], vecBombsiteMin[2]);
			vecBombsiteMin[0] = vecBombsiteMin[0] - 32;
			vecBombsiteMin[1] = vecBombsiteMin[1] - 32;
			vecBombsiteMin[2] = vecBombsiteMin[2] - 32;
			if (bDebug) LogMessage("Min - hull: [ %f, %f, %f ]", vecBombsiteMin[0], vecBombsiteMin[1], vecBombsiteMin[2]);
			
			GetEntPropVector(BombsiteIndex[i], Prop_Send, "m_vecMaxs", vecBombsiteMax);
			if (bDebug) LogMessage("Max: [ %f, %f, %f ]", vecBombsiteMax[0], vecBombsiteMax[1], vecBombsiteMax[2]);
			vecBombsiteMax[0] = vecBombsiteMax[0] + 32;
			vecBombsiteMax[1] = vecBombsiteMax[1] + 32;
			vecBombsiteMax[2] = vecBombsiteMax[2] + 32;
			if (bDebug) LogMessage("Max + hull: [ %f, %f, %f ]", vecBombsiteMax[0], vecBombsiteMax[1], vecBombsiteMax[2]);

			if (IsVecBetween(c4origin, vecBombsiteMin, vecBombsiteMax))
			{
				if (bDebug) LogMessage("C4 spawned in bombsite ID: %i, entity ID: %i", BombsiteIndex[i], entity);
				//PrintToChatAll("C4 spawned in bombsite ID: %i, entity ID: %i", BombsiteIndex[i], entity);
				BombsiteMessage(i, 0);
				
				// Sometimes it's possible to plant bomb on same site twice, need to track that down.
				if (BombsitePlanted[i] != -1)
				{
					LogError("There's already planted C4 in bombsite with ID: %i", BombsiteIndex[i]);
					if (bDebug) PrintToChatAll("There's already planted C4 in bombsite with ID: %i", BombsiteIndex[i]);
					BombsitePlanted[i] = entity;
				}
				else
				{
					BombsitePlanted[i] = entity;
				}
				return;
			}
		}
	}
}

public Action Event_BombPlanted(Event event, const char[] name, bool dontBroadcast) 
{
	LogMessage("[Bombing Mode] Event: Bomb Planted.");
	
	// Give another C4 to player who planted bomb.
	int client_index = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!client_index) return Plugin_Continue;
	
	GameRules_SetProp("m_bBombPlanted", 0);
	bRoundTimerStop = true;
	//PrintToChatAll("[Bombing Mode] Paused round timer: %i seconds left", iRoundTime);
	LogMessage("[Bombing Mode] Paused round timer: %i seconds left", iRoundTime);
	if (IsPlayerAlive(client_index)) CreateTimer(0.1, Event_GiveC4ToPlayer, client_index);
	// Find out why model disappear.
	int c4ent = -1;
	while ((c4ent = FindEntityByClassname(c4ent, "planted_c4")) != -1) 
	{
		int c4ticking = GetEntProp(c4ent, Prop_Send, "m_bBombTicking");
		int c4modelindex = GetEntProp(c4ent, Prop_Send, "m_nModelIndex");
		int c4rendermode = GetEntProp(c4ent, Prop_Send, "m_nRenderMode");
		int c4renderfx = GetEntProp(c4ent, Prop_Send, "m_nRenderFX");
		if (c4ticking == 1)
		{
			if (bDebug) PrintToChatAll("[Bombing Mode] Bomb ID: %i, Model Index: %i, Render Mode: %i, RenderFX: %i", c4ent, c4modelindex, c4rendermode, c4renderfx);
		}
	}
	return Plugin_Continue;
}

public Action Event_BombDefused(Event event, const char[] name, bool dontBroadcast) 
{
	LogMessage("[Bombing Mode] Event: Bomb Defused.");
	for ( int i = 0; i <= 3; i++ )
	{
		if (BombsitePlanted[i] != -1)
		{
			if (bDebug) LogMessage("[Bombing Mode] Bombsite ID: %i, C4 ID: %i", BombsiteIndex[i], BombsitePlanted[i]);
			int ticking = GetEntProp(BombsitePlanted[i], Prop_Send, "m_bBombTicking");
			int bdefused = GetEntProp(BombsitePlanted[i], Prop_Send, "m_bBombDefused");
			if ( ticking == 0 && bdefused == 1 ) // Unless we have defused multiple bombs simultaneously, it should work fine, I guess.
			{
				LogMessage("[Bombing Mode] Bomb Defused - Bombsite ID: %i", BombsiteIndex[i]);
				//PrintToChatAll("[Bombing Mode] Bomb Defused - Bombsite ID: %i", BombsiteIndex[i]);
				BombsiteMessage(i, 1);
				BombsitePlanted[i] = -1;
				if (bDebug) LogMessage("[Bombing Mode] Bombsite ID: %i, C4 ID: %i", BombsiteIndex[i], BombsitePlanted[i]);
				
				for ( int client = 1; client <= MaxClients; client++ )
				{
					if(IsValidPlayer(client) && !IsFakeClient(client))
					{
						EmitSoundToClient(client, "+radio/bombdef.wav", SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE);
					}
					PrintCenterTextAll("#Cstrike_TitlesTXT_Bomb_Defused");
				}
				
				// Give bonus money to teams;
				RewardTeam( CS_TEAM_CT, iRewardCTDefused, "Team award for defusing the C4.");
				int iRewardTLoseDefuse = iRewardTDefused + iRewardTeamLoser;
				RewardTeam( CS_TEAM_T, iRewardTLoseDefuse, "Team bonus for planting the bomb.");
				
				// Find all non-ticking C4 and delete them.
				int c4count = 0;
				int c4inactive = 0;
				int c4defusedent = -1;
				while ((c4defusedent = FindEntityByClassname(c4defusedent, "planted_c4")) != -1) 
				{
					int c4ticking = GetEntProp(c4defusedent, Prop_Send, "m_bBombTicking");
					c4count++;
					if (c4ticking == 0)
					{
						c4inactive++;
						AcceptEntityInput(c4defusedent, "Kill");
					}
				}
				// Unpause timer
				if (c4count <= c4inactive)
				{
					bRoundTimerStop = false;
					PrintToChatAll("[Bombing Mode] Unpaused round timer: %i seconds left.", iRoundTime);
					LogMessage("[Bombing Mode] Unpaused round timer: %i seconds left.", iRoundTime);
				}
				return Plugin_Continue;
			}
		}
	}
	
	LogError("[Bombing Mode] Bomb defused, but planted_c4 ID is invalid.");
	if (bDebug) PrintToChatAll("[Bombing Mode] Bomb defused, but planted_c4 ID is invalid.");
	return Plugin_Continue;
}

public Action Event_BombExploded(Event event, const char[] name, bool dontBroadcast) 
{
	LogMessage("[Bombing Mode] Event: Bomb Exploded.");
	for ( int i = 0; i <= 3; i++ )
	{
		LogMessage("[Bombing Mode] Bombsite ID: %i, C4 ID: %i", BombsiteIndex[i], BombsitePlanted[i]);
		if (BombsitePlanted[i] != -1)
		{
			LogMessage("[Bombing Mode] Bombsite ID: %i, C4 ID: %i", BombsiteIndex[i], BombsitePlanted[i]);
			if (BombsiteExploded[i] != 1)
			{
				int ticking = GetEntProp(BombsitePlanted[i], Prop_Send, "m_bBombTicking");
				int bdefused = GetEntProp(BombsitePlanted[i], Prop_Send, "m_bBombDefused");
				
				if ( ticking == 0 && bdefused == 0 ) // Unless we have defused multiple bombs simultaneously, it should work fine, I guess.
				{
					BombsiteExploded[i] = 1;
					BombsitesCountExploded++;
					LogMessage("[Bombing Mode] Bomb Exploded - Bombsite ID: %i, Exploded: %i, BombsitesCount: %i.", BombsiteIndex[i], BombsitesCountExploded, BombsitesCount);
					//PrintToChatAll("[Bombing Mode] Bomb Exploded - Bombsite ID: %i, Exploded: %i, BombsitesCount: %i.", BombsiteIndex[i], BombsitesCountExploded, BombsitesCount);
					BombsiteMessage(i, 2);
					BombsitePlanted[i] = -1;
					if (bDebug) LogMessage("[Bombing Mode] Bombsite ID: %i, C4 ID: %i", BombsiteIndex[i], BombsitePlanted[i]);
					
					if ( BombsitesCountExploded >= BombsitesCount )
					{
						if (!bEndingRound)
						{
							//PrintToChatAll("[Bombing Mode] Sending T Win event...");
							if (bDebug) LogMessage("[Bombing Mode] Sending T Win event...");
							
							int iEntGameEnd = -1;
							iEntGameEnd = FindEntityByClassname(iEntGameEnd, "game_round_end");
							
							if (iEntGameEnd < 1)
							{
								iEntGameEnd = CreateEntityByName("game_round_end");
								if (IsValidEntity(iEntGameEnd)) 
								{
									if (bDebug) LogMessage("[Bombing Mode] Can't find game_round_end entity, creating a new one.");
									DispatchSpawn(iEntGameEnd);
								}
								else
								{
									LogError("[Bombing Mode] Unable to find or create a game_round_end entity.");
									if (bDebug) PrintToChatAll("[Bombing Mode] Unable to find or create a game_round_end entity.");
									return Plugin_Continue;
								}
							}
							
							if (roundtimer != INVALID_HANDLE)
							{
								delete roundtimer;
							}
							float flRoundDelay = GetConVarFloat(RoundDelayRestart);
							SetVariantFloat(flRoundDelay);
							AcceptEntityInput(iEntGameEnd, "EndRound_TerroristsWin");
							bEndingRound = true;
						}
					}
					// Add round time and check for planted bombs
					else 
					{
						// Give bonus money to teams;
						RewardTeam( CS_TEAM_T, iRewardTExploded, "Team award for detonating bomb.");
						RewardTeam( CS_TEAM_CT, iRewardTeamLoser, "Team bonus.");
						
						int iCvarAddTime = RoundToZero(GetConVarFloat(RoundTime) * 60); // GO uses minutes
						iRoundTime = iRoundTime + iCvarAddTime;
						//PrintToChatAll("[Bombing Mode] Added bonus time: %i seconds left", iRoundTime);
						LogMessage("[Bombing Mode] Added bonus time: %i seconds left", iRoundTime);
						
						int c4active = 0;
						int c4ent = -1;
						while ((c4ent = FindEntityByClassname(c4ent, "planted_c4")) != -1) 
						{
							int c4ticking = GetEntProp(c4ent, Prop_Send, "m_bBombTicking");
							int c4modelindex = GetEntProp(c4ent, Prop_Send, "m_nModelIndex");
							int c4rendermode = GetEntProp(c4ent, Prop_Send, "m_nRenderMode");
							int c4renderfx = GetEntProp(c4ent, Prop_Send, "m_nRenderFX");
							if (c4ticking == 1)
							{
								c4active++;
								if (bDebug) PrintToChatAll("[Bombing Mode] Bomb ID: %i, Model Index: %i, Render Mode: %i, RenderFX: %i", c4ent, c4modelindex, c4rendermode, c4renderfx);
								// Set model to C4.
								SetEntityModel(c4ent, "models/weapons/w_ied_dropped.mdl");
							}
							else 
							{
								AcceptEntityInput(c4ent, "Kill");
							}
						}
						// Unpause timer
						if (c4active > 0)
						{
							bRoundTimerStop = true;
							PrintToChatAll("[Bombing Mode] There's active C4 - timer stays paused.");
							LogMessage("[Bombing Mode] There's active C4 - timer stays paused.");
						}
						else
						{
							bRoundTimerStop = false;
							PrintToChatAll("[Bombing Mode] Unpaused round timer: %i seconds left.", iRoundTime);
							LogMessage("[Bombing Mode] Unpaused round timer: %i seconds left.", iRoundTime);
						}	
					}
					return Plugin_Continue;
				}
			}
			else 
			{
				LogError("[Bombing Mode] Incorrect Bombsite ID, target has been already detonated.");
				if (bDebug) PrintToChatAll("[Bombing Mode] Incorrect Bombsite ID, target has been already detonated.");
				return Plugin_Continue;
			}
		}
	}
	LogError("[Bombing Mode] Bomb exploded, but planted_c4 ID is invalid.");
	if (bDebug) PrintToChatAll("[Bombing Mode] Bomb exploded, but planted_c4 ID is invalid.");
	return Plugin_Continue;
}
//==========//

//=== General stocks ===//
stock bool IsVecBetween(float vecVector[3], float vecMin[3], float vecMax[3]) 
{
  return ((vecMin[0] <= vecVector[0] <= vecMax[0]) && (vecMin[1] <= vecVector[1] <= vecMax[1]) && (vecMin[2] <= vecVector[2] <= vecMax[2]));
}
//==========//