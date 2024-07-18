#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
#include <dhooks>
#include <tf2_stocks>
#include <vscript>

#define COLLISION_GROUP_PLAYER_MOVEMENT 8
#define CONTENTS_REDTEAM 0x800
#define CONTENTS_BLUETEAM 0x1000

// DHooks
static ArrayList g_DynamicHookIds;
static DynamicHook g_DHook_CTFProjectile_Jar_PipebombTouch;
static DynamicHook g_DHook_CTFBaseBoss_GetCurrencyValue;
static DynamicHook g_DHook_IBody_StartActivity;
// VScript Hooks
// VScript Detours
DynamicDetour g_Detour_ScriptAddGesture;
DynamicDetour g_Detour_ScriptAddGestureSequence;
// Base SDK Calls
static Handle g_SDKCall_CTFProjectile_Jar_VPhysicsCollisionThink;
static Handle g_SDKCall_AddGestureSequence;
static Handle g_SDKCall_AddGesture;
static Handle g_SDKCall_hMyNextBotPointer;
static Handle g_SDKCall_GetBodyInterface;
// VScript SDK Calls
static Handle g_SDKCall_ScriptTakeDamageCustom;
//static Handle g_SDKCall_ScriptGetBodyInterface;

static int g_iWeaponProjectileType;

enum TF_Team
{
	TF_Team_Unassigned = 0,
	TF_Team_Spectator = 1,
	TF_Team_Red = 2,
	TF_Team_Blue = 3,
    TF_Team_Halloween = 5
};

public Plugin myinfo =
{
    name = "Base Boss Fixes",
    author = "Gazyi",
    description = "Various changes to base_boss entity that can't be done with VScript",
    version = "1.0.0"
};

public void OnPluginStart()
{
    // DHooks
    g_DynamicHookIds = new ArrayList();

    GameData conf = LoadGameConfigFile( "basebot_fix.games" );
    g_DHook_CTFProjectile_Jar_PipebombTouch = DHooks_AddDynamicHook( conf, "CTFProjectile_Jar::PipebombTouch" );
    g_DHook_CTFBaseBoss_GetCurrencyValue = DHooks_AddDynamicHook( conf, "CTFBaseBoss::GetCurrencyValue" );
    g_DHook_IBody_StartActivity = DHooks_AddDynamicHook( conf, "IBody::StartActivity" );
    //g_DHook_IBody_StartActivity = DHookCreate( conf, "IBody::StartActivity", HookType_Raw, ReturnType_Bool, ThisPointer_Address, DHookCallback_IBody_StartActivity );

    // Additional offsets
    g_iWeaponProjectileType = FindSendPropInfo( "CTFGrenadePipebombProjectile", "m_iType" );

    // Base SDKCalls
    StartPrepSDKCall( SDKCall_Entity );
    PrepSDKCall_SetFromConf( conf, SDKConf_Signature, "CTFProjectile_Jar::VPhysicsCollisionThink" );
    g_SDKCall_CTFProjectile_Jar_VPhysicsCollisionThink = EndPrepSDKCall();
    if ( !g_SDKCall_CTFProjectile_Jar_VPhysicsCollisionThink )
        SetFailState( "[Gamedata] Could not find CTFProjectile_Jar::VPhysicsCollisionThink" );

    StartPrepSDKCall( SDKCall_Entity );
    PrepSDKCall_SetFromConf( conf, SDKConf_Signature, "CBaseAnimatingOverlay::AddGestureSequence" );
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); // int sequence
    PrepSDKCall_AddParameter( SDKType_Bool, SDKPass_Plain ); // bool autokill
    PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain ); // int iLayer
    g_SDKCall_AddGestureSequence = EndPrepSDKCall();
    if ( !g_SDKCall_AddGestureSequence )
        SetFailState( "[Gamedata] Could not find CBaseAnimatingOverlay::AddGestureSequence" );

    StartPrepSDKCall( SDKCall_Entity );
    PrepSDKCall_SetFromConf( conf, SDKConf_Signature, "CBaseAnimatingOverlay::AddGesture" );
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); // int activity
    PrepSDKCall_AddParameter( SDKType_Bool, SDKPass_Plain ); // bool autokill
    PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain ); // int iLayer
    g_SDKCall_AddGesture = EndPrepSDKCall();
    if ( !g_SDKCall_AddGesture )
        SetFailState( "[Gamedata] Could not find CBaseAnimatingOverlay::AddGesture" );

    StartPrepSDKCall( SDKCall_Entity );
	PrepSDKCall_SetFromConf( conf, SDKConf_Virtual, "CBaseEntity::MyNextBotPointer" );
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	if ((g_SDKCall_hMyNextBotPointer = EndPrepSDKCall()) == INVALID_HANDLE)
        SetFailState("Failed to create SDKCall for CBaseEntity::MyNextBotPointer offset!");
    
    StartPrepSDKCall( SDKCall_Raw );
	PrepSDKCall_SetFromConf( conf, SDKConf_Virtual, "INextBot::GetBodyInterface" );
	PrepSDKCall_SetReturnInfo( SDKType_PlainOldData, SDKPass_Plain );
	if((g_SDKCall_GetBodyInterface = EndPrepSDKCall()) == INVALID_HANDLE)
        SetFailState("Failed to create Virtual Call for INextBot::GetBodyInterface!");
}

public void OnMapStart()
{
    // New VScript functions
    // CBaseAnimating::AddGestureSequence( int sequence )
    VScriptFunction hScriptAddGestureSequence = VScript_CreateClassFunction( "CBaseAnimating", "AddGestureSequence" );
    hScriptAddGestureSequence.SetParam( 1, FIELD_INTEGER );
    hScriptAddGestureSequence.Return = FIELD_INTEGER;
    hScriptAddGestureSequence.SetFunctionEmpty();

    // CBaseAnimating::AddGesture( int activity )
    VScriptFunction hScriptAddGesture = VScript_CreateClassFunction( "CBaseAnimating", "AddGesture" );
    hScriptAddGesture.SetParam( 1, FIELD_INTEGER );
    hScriptAddGesture.Return = FIELD_INTEGER;
    hScriptAddGesture.SetFunctionEmpty();
    VScript_ResetScriptVM();

    g_Detour_ScriptAddGesture = hScriptAddGesture.CreateDetour();
    g_Detour_ScriptAddGesture.Enable( Hook_Pre, Detour_AddGesture );
    g_Detour_ScriptAddGestureSequence = hScriptAddGestureSequence.CreateDetour();
    g_Detour_ScriptAddGestureSequence.Enable( Hook_Pre, Detour_AddGestureSequence );

    // SDK Calls
    VScriptFunction hScriptTakeDamageCustom = VScript_GetClassFunction( "CBaseEntity", "TakeDamageCustom" );
    if ( !hScriptTakeDamageCustom )
        SetFailState( "[VScript] Could not find script function CBaseEntity::TakeDamageCustom" );

    g_SDKCall_ScriptTakeDamageCustom = hScriptTakeDamageCustom.CreateSDKCall();
    /*
    VScriptFunction hScriptGetBodyInterface = VScript_GetClassFunction( "NextBotCombatCharacter", "GetBodyInterface" );
    if ( !hScriptGetBodyInterface )
        SetFailState( "[VScript] Could not find script function NextBotCombatCharacter::GetBodyInterface" );

    g_SDKCall_ScriptGetBodyInterface = hScriptGetBodyInterface.CreateSDKCall()
    */
}

public void OnEntityCreated( int entity, const char[] classname )
{
    if ( StrEqual( classname, "base_boss" ) )
    {
        SDKHook( entity, SDKHook_TraceAttackPost, PostTraceAttack );
        SDKHook( entity, SDKHook_ShouldCollide, ShouldCollide );
        SetEntData( entity, FindSendPropInfo( "CTFBaseBoss", "m_lastHealthPercentage" ) + 28, false, 4, true );	// bool m_bResolvePlayerCollisions
        DHooks_HookEntity( g_DHook_CTFBaseBoss_GetCurrencyValue, Hook_Pre, entity, DHookCallback_BaseBoss_GetCurrencyValue );
        // Maybe there's a way to get INextBotComponent from script scope too, but it didn't work out, so let's use old method.
        Address pNB = SDKCall( g_SDKCall_hMyNextBotPointer, entity );
        Address pBody = SDKCall( g_SDKCall_GetBodyInterface, pNB );
        g_DHook_IBody_StartActivity.HookRaw( Hook_Post, pBody, DHookCallback_IBody_StartActivity );
    }

    if ( StrEqual( classname, "tf_projectile_jar" ) || StrEqual( classname, "tf_projectile_jar_milk" ) || StrEqual( classname, "tf_projectile_cleaver" ) )
        DHooks_HookEntity( g_DHook_CTFProjectile_Jar_PipebombTouch, Hook_Post, entity, DHookCallback_Jar_PipebombTouch_Post );
}

// Team collision
public bool ShouldCollide( int entity, int collisiongroup, int contentsmask, bool originalResult )
{
    if ( collisiongroup == COLLISION_GROUP_PLAYER_MOVEMENT )
    {
        int iTeam = GetEntProp( entity, Prop_Data, "m_iTeamNum" );
        
        switch( view_as<TF_Team>(iTeam) )
        {
            case TF_Team_Red:
            {
                if ( !( contentsmask & CONTENTS_REDTEAM ) )
                    return false;
            }
            case TF_Team_Blue:
            {
                if ( !( contentsmask & CONTENTS_BLUETEAM ) )
                    return false;
            }
        }
    }
    return originalResult;
}

// Headshots
public void PostTraceAttack( int victim, int attacker, int inflictor, float damage, int damagetype, int ammotype, int hitbox, int hitgroup )
{
    SetEntProp( victim, Prop_Data, "m_LastHitGroup", hitgroup );
    //PrintToServer( "Hitgroup: %i", hitgroup );
    //SDKCall( g_SDKCall_AddGestureSequence, victim, 301, true ); // Works
    //SDKCall( g_SDKCall_AddGesture, victim, 1389, true ); // Works
}

// Throwables collision.
static MRESReturn DHookCallback_Jar_PipebombTouch_Post( int entity, DHookParam params )
{
    char cls[32];
    char prj_cls[32];
    GetEntityClassname( params.Get(1), cls, sizeof(cls) );
    GetEntityClassname( entity, prj_cls, sizeof(prj_cls) );
    PrintToServer( "Projectile ID: %i", entity );
    PrintToServer( "Hit Entity: %i", params.Get(1) );
    PrintToServer( "Entity Classname: %s", cls );

    if ( StrEqual( cls, "base_boss" ) && GetEntProp( entity, Prop_Send, "m_bTouched") == 0 )
    {
        SetEntProp( entity, Prop_Send, "m_bTouched", true );
    
        // Jarate and Mad Milk explode on contact
        if ( StrEqual( prj_cls, "tf_projectile_jar" ) || StrEqual( prj_cls, "tf_projectile_jar_milk" ) )
        {
            //PrintToServer( "Jar hit Merc!" );
            SDKCall( g_SDKCall_CTFProjectile_Jar_VPhysicsCollisionThink, entity );
        }
        else if ( StrEqual( prj_cls, "tf_projectile_cleaver" ) && ( GetEntProp( entity, Prop_Data, "m_iTeamNum" ) != GetEntProp( params.Get(1), Prop_Data, "m_iTeamNum" ) ) )
        {
            // Cleaver applies damage on hit and adds bleeding.
            int entAttacker = GetEntPropEnt( entity, Prop_Send, "m_hThrower" );
            int entWeapon = GetEntPropEnt( entity, Prop_Send, "m_hLauncher" );
            int isCritical = GetEntProp( entity, Prop_Send, "m_bCritical" );
            float pos[3]; 
            GetEntPropVector( entity, Prop_Data, "m_vecAbsOrigin", pos );
            float flDamage = 50.0;
            int damageType = DMG_SLASH;
            int customDamage = TF_CUSTOM_CLEAVER;

            PrintToServer( "entAttacker: %i", entAttacker );
            PrintToServer( "entWeapon: %i", entWeapon );
            PrintToServer( "Crit: %i", isCritical );

            if ( isCritical != 0 )
            {
                damageType |= DMG_ACID;
                customDamage = TF_CUSTOM_CLEAVER_CRIT;
            }

            float flTime = GetGameTime() - GetEntDataFloat( entity, g_iWeaponProjectileType + 0x04 );
            PrintToServer( "Lifetime: %f", flTime );

            // Mini-crit on long distances
            /*
            if ( flTime >= 0.5 )
                customDamage = TF_CUSTOM_CLEAVER_CRIT;
            */
            // TakeDamageCustom
            // handle hInflictor
            // handle hAttacker
            // handle hWeapon
            // Vector vecDamageForce
            // Vector vecDamagePosition
            // float flDamage
            // int nDamageType
            // Constants.ETFDmgCustom nCustomDamageType
            SDKCall( g_SDKCall_ScriptTakeDamageCustom, params.Get(1), VScript_EntityToHScript( entWeapon ), VScript_EntityToHScript( entAttacker ), VScript_EntityToHScript( entWeapon ), NULL_VECTOR, pos, flDamage, damageType, customDamage );

            // Hit sound is handled by Vscript
            int enteffects = GetEntProp( entity, Prop_Send, "m_fEffects" );
            enteffects |= 32; // EF_NODRAW
		    SetEntProp( entity, Prop_Send, "m_fEffects", enteffects );
            SetEntityCollisionGroup( entity, 10 ); // COLLISION_GROUP_IN_VEHICLE
            CreateTimer( 0.2, CleaverDespawn, entity, TIMER_FLAG_NO_MAPCHANGE );
            return MRES_Supercede;
        }
    }
    return MRES_Ignored;
}

// Don't drop money on kill event. If these are dropped, it's a bug, which happens when NPC has negative health and get damaged.
static MRESReturn DHookCallback_BaseBoss_GetCurrencyValue( Address pThis, Handle hReturn, Handle hParams )
{
    PrintToServer( "CTFBaseBoss:GetCurrencyValue called!" );
    DHookSetReturn( hReturn, 0 );
    return MRES_Supercede;
}

static MRESReturn DHookCallback_IBody_StartActivity( Address pThis, Handle hReturn, Handle hParams )
{ 
    DHookSetReturn( hReturn, true );
    return MRES_Supercede;
}

static MRESReturn Detour_AddGesture( int entity, DHookReturn hReturn, DHookParam hParams )
{
    int iLayer = SDKCall( g_SDKCall_AddGesture, entity, hParams.Get(1), true );
    hReturn.Value = iLayer;
	return MRES_Supercede;
}

static MRESReturn Detour_AddGestureSequence( int entity, DHookReturn hReturn, DHookParam hParams )
{
    int iLayer = SDKCall( g_SDKCall_AddGestureSequence, entity, hParams.Get(1), true );
    hReturn.Value = iLayer;
	return MRES_Supercede;
}

public Action CleaverDespawn( Handle timer, int entity )
{
    if ( IsValidEntity( entity ) )
        AcceptEntityInput( entity, "Kill" );

    return Plugin_Handled;
}

static void DHooks_HookEntity( DynamicHook hook, HookMode mode, int entity, DHookCallback callback )
{
    if (hook)
    {
        int hookid = hook.HookEntity( mode, entity, callback, DHookRemovalCB_OnHookRemoved );
        if (hookid != INVALID_HOOK_ID)
        {
            g_DynamicHookIds.Push( hookid );
        }
    }
}

public void DHookRemovalCB_OnHookRemoved( int hookid )
{
    int index = g_DynamicHookIds.FindValue( hookid );
    if ( index != -1 )
    {
        g_DynamicHookIds.Erase( index );
    }
}

static DynamicHook DHooks_AddDynamicHook( GameData gamedata, const char[] name )
{
    DynamicHook hook = DynamicHook.FromConf( gamedata, name );
    if ( !hook )
    {
        LogError( "Failed to create hook setup handle for %s", name );
    }
    return hook;
}