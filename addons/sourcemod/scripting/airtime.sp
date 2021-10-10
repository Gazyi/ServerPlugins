#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

static const int FRAMESKIP = 3;
static int skippedframes = 0;

float flPlayerNetprop[MAXPLAYERS+1];
int iPlayerUnderwater[MAXPLAYERS+1] = {0, ...};

// Handles for plugin convars.
Handle airtime_enable;
Handle airtime_debug;
Handle airtime_time;

// ConVar Cache.
bool bAirTimeEnabled = false;
bool bAirTimeDebug = false;
float flAirTime = 12.0;
float flDefaultAirTime = 12.0; // Default air time in non-HL2 games.

public Plugin myinfo =
{
	name = "Air Time",
	description = "Allows to change underwater time and disable drowning.",
	author = "Gazyi",
	version = "1.0.0"
};

public void OnPluginStart()
{
	airtime_enable = CreateConVar("sm_airtime_enabled", "1", "Enable Air Time Plugin.\n0 = Disabled\n1 = Enabled", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	airtime_debug = CreateConVar("sm_airtime_debug", "1", "Debug Mode.\n0 = Disabled\n1 = Enabled", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	airtime_time = CreateConVar("sm_airtime_time", "12.0", "How many seconds players can be underwater without drowning. Negative number disables drowning.", FCVAR_NOTIFY);
	
	//Convar Changes hooks
	HookConVarChange(airtime_enable, CvarChanged);
	HookConVarChange(airtime_debug, CvarChanged);
	HookConVarChange(airtime_time, CvarChanged);
	
	CacheCvars();
}

public void CvarChanged(Handle cvar, const char[] oldvalue, const char[] newvalue)
{
	if (cvar == airtime_enable)
		bAirTimeEnabled = GetConVarBool(airtime_enable);
	if (cvar == airtime_debug)
		bAirTimeDebug = GetConVarBool(airtime_debug);
	if (cvar == airtime_time)
		flAirTime = GetConVarFloat(airtime_time);
}

public void CacheCvars()
{
	bAirTimeEnabled = GetConVarBool(airtime_enable);
	bAirTimeDebug = GetConVarBool(airtime_debug);
	flAirTime = GetConVarFloat(airtime_time);
}

public void OnGameFrame()
{
	if (!bAirTimeEnabled) return;
	if (!IsServerProcessing()) return;
	
	skippedframes++;
	
	for (int i = 1; i <= MaxClients; ++i)
	{
		//if (IsValidEntity(i) && IsClientInGame(i) && GetClientTeam(i) > 1 && (GetEntityFlags(i) & FL_INWATER))
		if (IsValidEntity(i) && IsClientInGame(i) && IsPlayerAlive(i) && (GetEntityFlags(i) & FL_INWATER))
		{	
			int iWaterLevel = GetEntProp(i, Prop_Send, "m_nWaterLevel");
			if (iWaterLevel > 2) // 0: no water, 1: a little, 2: half body, 3: full body under water
			{
				if (iPlayerUnderwater[i] == 0) SetAirTime(i);
				if (bAirTimeDebug)
				{
					if (skippedframes >= FRAMESKIP)
					{
						skippedframes = 0;
						float airtime_duration = flPlayerNetprop[i] - GetGameTime();
						PrintToServer("Client %i, Air time: %.2f seconds.", i, airtime_duration);
					}
				}
			}
			else
			{
				if (iPlayerUnderwater[i] != 0) iPlayerUnderwater[i] = 0; // Maybe there's a better solution than updating this every frame.
				if (bAirTimeDebug) PrintToServer("Client %i, Underwater flag: %i", i, iPlayerUnderwater[i]);
			}
		}
	}
}

void SetAirTime(int client)
{
	flPlayerNetprop[client] = GetEntPropFloat(client, Prop_Data, "m_AirFinished");
	if (bAirTimeDebug) PrintToServer("Client %i, m_AirFinished: %f", client, flPlayerNetprop[client]);
	if (flAirTime >= 0.0)
	{
		flPlayerNetprop[client] = flPlayerNetprop[client] + (flAirTime - 12.0);
		iPlayerUnderwater[client] = 1;
		if (bAirTimeDebug)
		{
			PrintToServer("Client %i, new m_AirFinished: %f", client, flPlayerNetprop[client]);
			PrintToServer("Set Client %i underwater flag to %i", client, iPlayerUnderwater[client]);
		}
	}
	else
	{
		flPlayerNetprop[client] = GetGameTime() + flDefaultAirTime; // Maybe there's a better solution than updating this every frame.
	}
	SetEntPropFloat(client, Prop_Data, "m_AirFinished", flPlayerNetprop[client]);
}