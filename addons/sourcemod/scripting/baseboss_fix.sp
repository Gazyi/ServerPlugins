#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
#include <dhooks>
#include <tf2_stocks>
#include <vscript>

static ArrayList g_DynamicHookIds;
static DynamicHook g_DHook_CTFProjectile_Jar_PipebombTouch;
static Handle g_SDKCall_CTFProjectile_Jar_VPhysicsCollisionThink;
static Handle g_SDKCall_ScriptTakeDamageCustom;

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

    // SDKCalls
    StartPrepSDKCall( SDKCall_Entity );
    PrepSDKCall_SetFromConf( conf, SDKConf_Signature, "CTFProjectile_Jar::VPhysicsCollisionThink" );
    g_SDKCall_CTFProjectile_Jar_VPhysicsCollisionThink = EndPrepSDKCall();

    if ( !g_SDKCall_CTFProjectile_Jar_VPhysicsCollisionThink )
        SetFailState( "[Gamedata] Could not find CTFProjectile_Jar::VPhysicsCollisionThink" );

    delete conf;
}

public void OnMapStart()
{
    VScriptFunction hScriptTakeDamageCustom = VScript_GetClassFunction( "CBaseEntity", "TakeDamageCustom" );

    if ( !hScriptTakeDamageCustom )
        SetFailState( "[VScript] Could not find CBaseEntity::TakeDamageCustom" );

    g_SDKCall_ScriptTakeDamageCustom = hScriptTakeDamageCustom.CreateSDKCall();
}

public void OnEntityCreated( int entity, const char[] classname )
{
    if ( StrEqual( classname, "base_boss" ) )
        SDKHook( entity, SDKHook_TraceAttackPost, PostTraceAttack );

    if ( StrEqual( classname, "tf_projectile_jar" ) || StrEqual( classname, "tf_projectile_jar_milk" ) || StrEqual( classname, "tf_projectile_cleaver" ) )
        DHooks_HookEntity( g_DHook_CTFProjectile_Jar_PipebombTouch, Hook_Post, entity, DHookCallback_Jar_PipebombTouch_Post );
}

// Headshots
public void PostTraceAttack( int victim, int attacker, int inflictor, float damage, int damagetype, int ammotype, int hitbox, int hitgroup )
{
    SetEntProp( victim, Prop_Data, "m_LastHitGroup", hitgroup );
    //PrintToServer( "Hitgroup: %i", hitgroup );
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
            PrintToServer( "Jar hit Merc!" );
            SDKCall( g_SDKCall_CTFProjectile_Jar_VPhysicsCollisionThink, entity );
        }
        else if ( StrEqual( prj_cls, "tf_projectile_cleaver" ) )
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
            SetEntityCollisionGroup( entity, 10 );
            CreateTimer( 0.2, CleaverDespawn, entity, TIMER_FLAG_NO_MAPCHANGE );
            return MRES_Supercede;
        }
    }
    return MRES_Ignored;
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