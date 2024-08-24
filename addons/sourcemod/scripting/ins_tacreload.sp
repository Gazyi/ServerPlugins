#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <dhooks>
#include <TheaterItemsAPI>

// SDK calls
static Handle hSDKCallIsSingleReload;
static Handle hSDKCallInsWeaponGetMaxClip1;
static Handle hSDKCallInsWeaponReload;
static Handle hSDKCallInstallUpgrade;
static Handle hSDKCallRemoveUpgrade;
static Handle hSDKCallDoAnimEvent;
static Handle hSDKCallWeaponIsReloading;
static Handle hSDKCallInsWeaponAbortReload;

// Dhooks
DynamicHook hDhookWeaponReload;
DynamicHook hDHookWeaponShouldLoseAmmoOnReload;
DynamicHook hDHookWeaponAbortReload;
DynamicHook hDHookWeaponFinishReload;
DynamicHook hDHookWeaponHolsterComplete;

// Detours
DynamicDetour hDetourWeaponGetReloadSpeedMod;

// Definitions
#define PLAYERANIMEVENT_RELOAD_ABORT 27
#define INPUT_RELOAD (1 << 11) // Insurgency has non-standart inputs.

// Config variables
ConVar g_CvarEnabled;
ConVar g_CvarDebug;
KeyValues hConfigKV;

// Player variables
Handle g_hReloadTimers[MAXPLAYERS+1];
int g_iWeaponMagUpgrades[MAXPLAYERS+1] = { -1, ... };
float g_flLastReloadInput[MAXPLAYERS+1] = { 0.0, ... };
float g_flPlayerDoubleTapTime[MAXPLAYERS+1] = { 0.35, ... };
bool g_bQueuedTacticalReload[MAXPLAYERS+1] = { false, ... };
bool g_bQueuedNormalReload[MAXPLAYERS+1] = { false, ... };

public Plugin myinfo =
{
    name = "Tactical Reload",
    author = "Gazyi",
    description = "Reload faster by dropping magazine ( Double tap reload button ).",
    version = "0.6.0"
};

public void OnPluginStart()
{
    char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "gamedata/ins_tacreload.games.txt");

    if (!FileExists(path))
		SetFailState("Can't find ins_tacreload.games.txt gamedata");

    GameData gamedata = LoadGameConfigFile("ins_tacreload.games");

    if (gamedata == INVALID_HANDLE)
		SetFailState("Can't find ins_tacreload.games.txt gamedata");

    // SDK Calls
    // IsSingleReload
    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CINSWeaponIsSingleReload");
    PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_ByValue);
    hSDKCallIsSingleReload = EndPrepSDKCall();
    if (!hSDKCallIsSingleReload)
        SetFailState( "Failed to create SDKCall: CINSWeapon::IsSingleReload" );

    // GetMaxClip1
    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf( gamedata, SDKConf_Virtual, "CINSWeaponGetMaxClip1" );
    PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
    hSDKCallInsWeaponGetMaxClip1 = EndPrepSDKCall();
    if (!hSDKCallInsWeaponGetMaxClip1)
        SetFailState( "Failed to create SDKCall: CINSWeapon::GetMaxClip1" );

    // Reload
    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf( gamedata, SDKConf_Virtual, "CINSWeaponReload" );
    PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_ByValue);
    hSDKCallInsWeaponReload = EndPrepSDKCall();
    if (!hSDKCallInsWeaponReload)
        SetFailState( "Failed to create SDKCall: CINSWeapon::Reload" );

    // InstallWeaponUpgrade
    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CINSWeaponInstallWeaponUpgrade");
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
    PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_ByValue);
    PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
    hSDKCallInstallUpgrade = EndPrepSDKCall();
    if (!hSDKCallInstallUpgrade)
        SetFailState( "Failed to create SDKCall: CINSWeapon::InstallWeaponUpgrade" );

    // RemoveWeaponUpgrade
    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CINSWeaponRemoveWeaponUpgrade");
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
    PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_ByValue);
    PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
    hSDKCallRemoveUpgrade = EndPrepSDKCall();
    if (!hSDKCallRemoveUpgrade)
        SetFailState( "Failed to create SDKCall: CINSWeapon::RemoveWeaponUpgrade" );

    // DoAnimationEvent
    StartPrepSDKCall(SDKCall_Player);
    PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CINSPlayerDoAnimationEvent");
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
    hSDKCallDoAnimEvent = EndPrepSDKCall();
    if (!hSDKCallDoAnimEvent)
        SetFailState( "Failed to create SDKCall: CINSPlayer::DoAnimationEvent" );

    // IsReloading
    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "CINSWeaponIsReloading");
    PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_ByValue);
    hSDKCallWeaponIsReloading = EndPrepSDKCall();
    if (!hSDKCallWeaponIsReloading)
        SetFailState( "Failed to create SDKCall: CINSWeapon::IsReloading" );

    // AbortReload
    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "CINSWeaponAbortReload");
    hSDKCallInsWeaponAbortReload = EndPrepSDKCall();
    if (!hSDKCallInsWeaponAbortReload)
        SetFailState( "Failed to create SDKCall: CINSWeapon::AbortReload" );

    // DHooks
    hDhookWeaponReload = DynamicHook.FromConf(gamedata, "HookCINSWeaponReload");
    if ( !hDhookWeaponReload )
		SetFailState("Failed to find hook function HookCINSWeaponReload");

    hDHookWeaponShouldLoseAmmoOnReload = DynamicHook.FromConf( gamedata, "HookCINSWeaponShouldLoseAmmoOnReload" );
    if ( !hDHookWeaponShouldLoseAmmoOnReload )
		SetFailState("Failed to find hook function CINSWeaponShouldLoseAmmoOnReload");

    hDHookWeaponAbortReload = DynamicHook.FromConf( gamedata, "HookCINSWeaponAbortReload" );
    if ( !hDHookWeaponAbortReload )
		SetFailState("Failed to find hook function CINSWeaponAbortReload");

    hDHookWeaponFinishReload = DynamicHook.FromConf( gamedata, "HookCINSWeaponFinishReload" );
    if ( !hDHookWeaponFinishReload )
		SetFailState("Failed to find hook function CINSWeaponFinishReload");

    hDHookWeaponHolsterComplete = DynamicHook.FromConf( gamedata, "HookCINSWeaponOnHolsterComplete" );
    if ( !hDHookWeaponHolsterComplete )
		SetFailState("Failed to find hook function CINSWeaponOnHolsterComplete");

    // Detours
        hDetourWeaponGetReloadSpeedMod = DynamicDetour.FromConf( gamedata, "DetourCINSWeaponGetReloadSpeedMod" );
    if ( !hDetourWeaponGetReloadSpeedMod )
		SetFailState("Failed to find function DetourCINSWeaponGetReloadSpeedMod");    
    hDetourWeaponGetReloadSpeedMod.Enable( Hook_Post, Detour_GetReloadSpeedPost );

    // Events
    HookEvent( "player_death", OnPlayerDeath );
    delete gamedata;

    char config[PLATFORM_MAX_PATH];
    BuildPath( Path_SM, config, sizeof(config), "configs/tacreload.cfg" );
    if ( !FileExists(config) )
        SetFailState( "Configuration file doesn't exist! Check for tacreload.cfg in configs folder!" );

    hConfigKV = new KeyValues( "TacReload" );
    FileToKeyValues( hConfigKV, config );

    g_CvarEnabled = CreateConVar( "ins_tacreload_enable", "1", "0/1 - Disable/Enable tactical reload plugin.", 0, true, 0.0, true, 1.0 );
    g_CvarDebug = CreateConVar( "ins_tacreload_debug", "0", "0/1 - Disable/Enable debug information", 0, true, 0.0, true, 1.0 );
    RegConsoleCmd( "ins_tacreload_delay", CmdSetReloadDelay, "Usage: ins_tacreload_delay <delay>. Values lower than 0.1 disable tactical reload." );
}

public Action CmdSetReloadDelay( int client, int args )
{
    if (args < 1)
    {
        PrintToChat( client, "Usage: ins_tacreload_delay <delay>. Values lower than 0.1 disable tactical reload." );
        return Plugin_Handled;
    }
    else
    {
        char arg[65];
        GetCmdArg( 1, arg, sizeof(arg) );
        float flDelay = StringToFloat( arg );
        g_flPlayerDoubleTapTime[ client ] = flDelay;
        return Plugin_Handled;
    }
}

public void OnClientDisconnect( int client )
{
    PlayerVariablesCleanup( client );
    g_flPlayerDoubleTapTime[ client ] = 0.35;
}

public void OnPlayerDeath( Event event, const char[] name, bool dontBroadcast )
{
    int client = GetClientOfUserId( event.GetInt( "userid" ) );
    if ( client > 0 && client <= MaxClients && IsClientConnected( client ) && IsClientInGame( client ) && !IsFakeClient( client ) )
        PlayerVariablesCleanup( client );
}

public void OnMapEnd()
{
    for ( int i=1; i<=MaxClients; i++ )
    {
        PlayerVariablesCleanup( i );
    }
}

public void PlayerVariablesCleanup( int client )
{
    delete g_hReloadTimers[ client ];
    g_iWeaponMagUpgrades[ client ] = -1;
    g_flLastReloadInput[ client ] = 0.0;
    g_bQueuedTacticalReload[ client ] = false;
    g_bQueuedNormalReload[ client ] = false;
}

public void OnEntityCreated( int entity, const char[] classname )
{
    if ( HasEntProp( entity, Prop_Data, "m_iClip1" ) )
        RequestFrame( OnWeaponCreated, EntIndexToEntRef( entity ) );
}

public void OnWeaponCreated( int iEntityRef )
{
    int entity = EntRefToEntIndex( iEntityRef );
    if ( entity == INVALID_ENT_REFERENCE )
        return;

    char classname[MAX_NAME_LENGTH];
    GetEntityClassname( entity, classname, sizeof(classname) );

    if ( IsValidWeapon( entity ) )
    {
        if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] Hooked %d , classname: %s", entity, classname );
        hDhookWeaponReload.HookEntity( Hook_Pre, entity, Dhook_CINSWeaponReload_Pre );
        hDHookWeaponShouldLoseAmmoOnReload.HookEntity( Hook_Post, entity, Dhook_CINSWeaponShouldLoseAmmoOnReload_Post );
        hDHookWeaponAbortReload.HookEntity( Hook_Post, entity, Dhook_CINSWeaponAbortReload_Post );
        hDHookWeaponFinishReload.HookEntity( Hook_Post, entity, Dhook_CINSWeaponFinishReload_Post );
        hDHookWeaponHolsterComplete.HookEntity( Hook_Post, entity, Dhook_CINSWeaponHolstered_Post );
    }
}

static MRESReturn Dhook_CINSWeaponReload_Pre( int entity, DHookReturn hReturn )
{
    if ( g_CvarEnabled.BoolValue )
    {
        if ( GameRules_GetProp( "m_iGameState" ) == 4 )
        {
            if ( GetEntProp( entity, Prop_Send, "m_iClip1" ) < SDKCall( hSDKCallInsWeaponGetMaxClip1, entity ) )
            {
                if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] Reload pre-hook!" );
                
                int iOwner = GetEntPropEnt( entity, Prop_Data, "m_hOwnerEntity" );

                if ( iOwner > 0 && iOwner <= MaxClients && IsClientConnected( iOwner ) && IsClientInGame( iOwner ) && IsPlayerAlive( iOwner ) && !IsFakeClient( iOwner ) && g_flPlayerDoubleTapTime[ iOwner ] >= 0.1 )
                {                               
                    if ( g_bQueuedTacticalReload[ iOwner ] )
                    {
                        if ( g_hReloadTimers[ iOwner ] != INVALID_HANDLE )
                            delete g_hReloadTimers[ iOwner ];
                            
                        PrepareForTacticalReload( entity, iOwner );

                        if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] Client %d. Tactical Reload.", iOwner );
                        
                        return MRES_Handled;
                    }

                    if ( !g_bQueuedNormalReload[ iOwner ] )
                    {
                        // Block original reload call.
                        DHookSetReturn( hReturn, false );
                        SDKCall( hSDKCallInsWeaponAbortReload, entity );

                        if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] Blocking original reload!" );

                        if ( g_hReloadTimers[ iOwner ] == INVALID_HANDLE )
                        {
                            // Call reload function after delay.
                            DataPack dpack;
                            g_hReloadTimers[ iOwner ] = CreateDataTimer( g_flPlayerDoubleTapTime[iOwner], DoNormalReload, dpack, TIMER_FLAG_NO_MAPCHANGE );
                            dpack.WriteCell( iOwner );
                            dpack.WriteCell( entity );
                            if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] Client %d. Normal Reload after delay.", iOwner );
                        }
                        return MRES_Supercede;
                    }
                }
            }
        }
    }
    return MRES_Ignored;
}

public Action DoNormalReload( Handle timer, DataPack dpack )
{
    dpack.Reset();
    int iOwner = dpack.ReadCell();
    int iWeapon = dpack.ReadCell();
    g_hReloadTimers[ iOwner ] = INVALID_HANDLE;

    if ( iOwner > 0 && iOwner <= MaxClients && IsClientConnected( iOwner ) && IsClientInGame( iOwner ) && IsPlayerAlive( iOwner ) && !IsFakeClient( iOwner ) )
    {
        g_bQueuedNormalReload[ iOwner ] = true;
        if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] Client %d. Calling Normal Reload.", iOwner );
        SDKCall( hSDKCallInsWeaponReload, iWeapon );
    }

    return Plugin_Continue;
}

static MRESReturn Dhook_CINSWeaponAbortReload_Post( int iWeaponEnt )
{   
    if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] CINSWeaponAbortReload called!" );
    int iOwner = GetEntPropEnt( iWeaponEnt, Prop_Data, "m_hOwnerEntity" );

    if ( !IsClientConnected(iOwner) || !IsClientInGame(iOwner) || !IsPlayerAlive(iOwner) || IsFakeClient(iOwner) )
        return MRES_Ignored;

    if ( g_bQueuedTacticalReload[ iOwner ] )
    {
        g_bQueuedTacticalReload[ iOwner ] = false;
        if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] Client %i unqueued for tactical reload.", iOwner );
        RemoveReloadUpgrades( iWeaponEnt );
    }
    g_bQueuedNormalReload[ iOwner ] = false;
    return MRES_Handled;
}

static MRESReturn Dhook_CINSWeaponFinishReload_Post( int iWeaponEnt )
{   
    if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] CINSWeaponFinishReload called!" );
    int iOwner = GetEntPropEnt( iWeaponEnt, Prop_Data, "m_hOwnerEntity" );

    if ( !IsClientConnected(iOwner) || !IsClientInGame(iOwner) || !IsPlayerAlive(iOwner) || IsFakeClient(iOwner) )
        return MRES_Ignored;

    if ( g_bQueuedTacticalReload[ iOwner ] )
    {
        g_bQueuedTacticalReload[ iOwner ] = false;
        if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] Client %i unqueued for tactical reload.", iOwner );
        RemoveReloadUpgrades( iWeaponEnt );
    }
    g_bQueuedNormalReload[ iOwner ] = false;
    return MRES_Handled;
}

static MRESReturn Dhook_CINSWeaponHolstered_Post( int iWeaponEnt ) 
{
    if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] CINSWeaponOnHolsterComplete called!" );
    int iOwner = GetEntPropEnt( iWeaponEnt, Prop_Data, "m_hOwnerEntity" );

    if ( iOwner > 0 && iOwner <= MaxClients && IsClientConnected( iOwner ) && IsClientInGame( iOwner ) && !IsFakeClient( iOwner ) )
    {
        if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] Client %i holstered weapon %i!", iOwner, iWeaponEnt );
        g_bQueuedTacticalReload[ iOwner ] = false;
        g_bQueuedNormalReload[ iOwner ] = false;
        if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] Client %i unqueued for reload.", iOwner );
        RemoveReloadUpgrades( iWeaponEnt );
        return MRES_Handled;
    }
    return MRES_Ignored;
}

static MRESReturn Dhook_CINSWeaponShouldLoseAmmoOnReload_Post( int entity, DHookReturn hReturn )
{   
    if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] ShouldLoseAmmoOnReload called! hReturn: %d", DHookGetReturn( hReturn ) );
    int iOwner = GetEntPropEnt( entity, Prop_Data, "m_hOwnerEntity" );
    if ( iOwner > 0 && iOwner <= MaxClients && IsClientConnected( iOwner ) && IsClientInGame( iOwner ) && !IsFakeClient( iOwner ) )
    {
        if ( g_bQueuedTacticalReload[ iOwner ] )
        {
            DHookSetReturn( hReturn, true );
            if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] Tactical reload! Override ShouldLoseAmmoOnReload value!" );
            return MRES_Override;
        }
    }
    return MRES_Ignored;
}

static MRESReturn Detour_GetReloadSpeedPost( int entity, DHookReturn hReturn )
{
    if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] GetReloadSpeed called!" );
    int iOwner = GetEntPropEnt( entity, Prop_Data, "m_hOwnerEntity" );
    if ( iOwner > 0 && iOwner <= MaxClients && IsClientConnected( iOwner ) && IsClientInGame( iOwner ) && !IsFakeClient( iOwner ) )
    {
        if ( g_bQueuedTacticalReload[ iOwner ] )
        {
            float flReloadSpeed = DHookGetReturn( hReturn );

            // Get weapon classname
            char szClassname[MAX_NAME_LENGTH];
            GetEntityClassname( entity, szClassname, sizeof(szClassname) );

            // Get original magazine slot upgrade
            char UpgradeName[MAX_NAME_LENGTH] = "default";
            int iMagUpgradeID = g_iWeaponMagUpgrades[ iOwner ];
            if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] Client: %i MagUpgradeID: %i", iOwner, iMagUpgradeID );

            if ( iMagUpgradeID != -1 )
                GetWeaponUpgradeItemName( iMagUpgradeID, UpgradeName, sizeof( UpgradeName ) );

            hConfigKV.Rewind();
            if ( hConfigKV.JumpToKey( UpgradeName ) )
            {
                char szSectionName[MAX_NAME_LENGTH];
                hConfigKV.GetSectionName( szSectionName, sizeof( szSectionName ) );
                if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] Found section: %s", szSectionName );
                if ( hConfigKV.JumpToKey( szClassname ) )
                {
                    hConfigKV.GetSectionName( szSectionName, sizeof( szSectionName ) );
                    if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] Found sub-section: %s", szSectionName );

                    flReloadSpeed *= hConfigKV.GetFloat( "tacreload_speed", 1.0 );
                    if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] New reload speed modifier: %.2f", flReloadSpeed );
                }
            }

            DHookSetReturn( hReturn, flReloadSpeed );
            return MRES_Override;
        }
    }
    return MRES_Ignored;
}

public void OnPlayerRunCmdPre(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
    if ( !g_CvarEnabled.BoolValue )
        return;

    if ( !IsClientConnected(client) || GameRules_GetProp( "m_iGameState" ) != 4 || !IsClientInGame(client) || !IsPlayerAlive(client) || IsFakeClient(client) )
        return;

    if ( g_flPlayerDoubleTapTime[ client ] < 0.1 )
        return;

    int iButtonsPressed = GetEntProp(client, Prop_Data, "m_afButtonPressed");
    int iButtonsReleased = GetEntProp(client, Prop_Data, "m_afButtonReleased");

    if ( buttons & INPUT_RELOAD && iButtonsPressed & INPUT_RELOAD )
    {
        char name[MAX_NAME_LENGTH];
        GetClientName(client, name, sizeof(name));
        if ( g_CvarDebug.BoolValue )
        {
            PrintToServer( "----------------------------------");
            PrintToServer( "Client %s pressed +reload!", name );
            PrintToServer( "Game Time: %f", GetGameTime() );
            PrintToServer( "g_flLastReloadInput: %f", g_flLastReloadInput[client] );
            PrintToServer( "----------------------------------");
        }
        if ( GetGameTime() - g_flLastReloadInput[client] < g_flPlayerDoubleTapTime[client] )
        {
            if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] %s does tactical reload!", name );
            int iWeaponEnt = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");

            if ( IsValidWeapon( iWeaponEnt ) )
            {
                // Full magazine
                int iClip1 = GetEntProp( iWeaponEnt, Prop_Send, "m_iClip1" );
                int iMaxClip1 = SDKCall( hSDKCallInsWeaponGetMaxClip1, iWeaponEnt );
                if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] m_iClip1: %i Max Clip1: %i", iClip1, iMaxClip1 );

                if ( iClip1 >= iMaxClip1 )
                {
                    if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] Magazine is full!" );
                    return;
                }
                
                // Already reloading.
                if ( HasEntProp( iWeaponEnt, Prop_Data, "m_bInReload" ) && view_as<bool>( GetEntProp( iWeaponEnt, Prop_Data, "m_bInReload" ) ) )
                    return;

                g_bQueuedTacticalReload[ client ] = true;
                if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] Client %i queued for tactical reload.", client );
                return;
            }
        }
    }

    if ( iButtonsReleased & INPUT_RELOAD )
    {
        g_flLastReloadInput[client] = GetGameTime();
        char name[MAX_NAME_LENGTH];
        GetClientName(client, name, sizeof(name));
        if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] Client %s released +reload!", name );
    }
}

stock void PrepareForTacticalReload( int iWeaponEnt, int iOwner )
{
    // Get weapon classname
    char szClassname[MAX_NAME_LENGTH];
    GetEntityClassname( iWeaponEnt, szClassname, sizeof(szClassname) );
    // Get upgrade from magazine slot
    int offset = GetEntSendPropOffs( iWeaponEnt, "m_upgradeSlots", true );
    int iMagUpgradeID = GetEntData( iWeaponEnt, offset + 8 ); // "magazine"
    if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] iWeaponEnt: %i, iMagUpgradeID: %i", iWeaponEnt, iMagUpgradeID );
    char UpgradeName[MAX_NAME_LENGTH] = "default";
    if ( iMagUpgradeID != -1 )
    {
        GetWeaponUpgradeItemName( iMagUpgradeID, UpgradeName, sizeof( UpgradeName ) );
    }
    hConfigKV.Rewind();
    if ( hConfigKV.JumpToKey( UpgradeName ) )
    {
        char szSectionName[MAX_NAME_LENGTH];
        hConfigKV.GetSectionName( szSectionName, sizeof( szSectionName ) );
        if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] Found section: %s", szSectionName );
        if ( hConfigKV.JumpToKey( szClassname ) )
        {
            hConfigKV.GetSectionName( szSectionName, sizeof( szSectionName ) );
            if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] Found sub-section: %s", szSectionName );

            // Store current Upgrade ID for restoration.
            g_iWeaponMagUpgrades[ iOwner ] = iMagUpgradeID;

            char TacReloadUpgradeName[MAX_NAME_LENGTH];
            hConfigKV.GetString( "tacreload_upgrade", TacReloadUpgradeName, sizeof( TacReloadUpgradeName ) );

            if ( strlen( TacReloadUpgradeName ) > 0 )
            {
                // Install upgrade
                if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] Upgrade name: %s", TacReloadUpgradeName );
                InstallWeaponUpgrade( iWeaponEnt, TacReloadUpgradeName );
            }
        }
    }
}

stock void InstallWeaponUpgrade( int iWeaponEnt, char[] upgradeName )
{
    // TODO: Find out how to get upgrade ID from code.
    int iUpgradeID = GetTheaterItemIdByWeaponUpgradeName( upgradeName );
    SDKCall( hSDKCallInstallUpgrade, iWeaponEnt, iUpgradeID, false );
    if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] Weapon upgrade %s installed on %i!", upgradeName, iWeaponEnt );
}

stock void RemoveReloadUpgrades( int iWeaponEnt )
{
    // Get upgrade from magazine slot
    int offset = GetEntSendPropOffs( iWeaponEnt, "m_upgradeSlots", true );
    int iMagUpgradeID = GetEntData( iWeaponEnt, offset + 8 ); // "magazine"

    if ( iMagUpgradeID != -1 )
    {
        int client = GetEntPropEnt( iWeaponEnt, Prop_Data, "m_hOwnerEntity" );
        if ( g_iWeaponMagUpgrades[ client ] != -1 )
        {
            if ( g_iWeaponMagUpgrades[ client ] != iMagUpgradeID )
            {
                // Restore original upgrade
                if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] Restoring weapon upgrade %i for entity %i!", g_iWeaponMagUpgrades[ client ], iWeaponEnt );
                SDKCall( hSDKCallInstallUpgrade, iWeaponEnt, g_iWeaponMagUpgrades[ client ], false );
                g_iWeaponMagUpgrades[ client ] = -1;
            }
        }
        else
        {
            if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] Removing weapon upgrade %i from entity %i", iMagUpgradeID, iWeaponEnt );
            SDKCall( hSDKCallRemoveUpgrade, iWeaponEnt, iMagUpgradeID, false );
        }
    }
}

stock void RemoveWeaponUpgrade( int iWeaponEnt, char[] upgradeName )
{
    // TODO: Find out how to get upgrade ID from code.
    int iUpgradeID = GetTheaterItemIdByWeaponUpgradeName( upgradeName );
    SDKCall( hSDKCallRemoveUpgrade, iWeaponEnt, iUpgradeID, false );
    if ( g_CvarDebug.BoolValue ) PrintToServer( "[TacReload] Weapon upgrade %s removed from %i!", upgradeName, iWeaponEnt );
}

stock bool IsValidWeapon( int iWeaponEnt )
{
    if ( iWeaponEnt > 0 && IsValidEdict( iWeaponEnt ) && IsValidEntity( iWeaponEnt ) )
    {
        // I don't know how to check real base class of entity since they return enthandles.
        // So I'm using netprops to check weapon class.

        // ignore rocket launchers
        if ( HasEntProp( iWeaponEnt, Prop_Send, "m_flLaunchWaitTime" ) )
            return false;
        
        if ( HasEntProp( iWeaponEnt, Prop_Send, "m_iClip1" ) )
        {
            // Exclude no clip weapons
            int iClipAmmo = GetEntProp( iWeaponEnt, Prop_Send, "m_iClip1" );
            if ( iClipAmmo == 255 || iClipAmmo < 0 )
                return false;
            
            // No tactical reload for weapons without magazines.
            bool isSingleReload = SDKCall( hSDKCallIsSingleReload, iWeaponEnt );

            if ( !isSingleReload )
                return true;
        }
    }
    return false;
}