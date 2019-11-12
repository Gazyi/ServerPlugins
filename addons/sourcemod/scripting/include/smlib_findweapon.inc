#include <sourcemod>
#include <sdktools_functions>

#define MAX_WEAPONS				48	// Max number of weapons available

/**
 * Checks if a client has a specific weapon.
 *
 * @param client 		Client Index.
 * @param className		Weapon Classname.
 * @return				True if client has the weapon, otherwise false.
 */
stock Client_HasWeapon(client, const String:className[])
{
	new weapon = Client_GetWeapon(client, className);
	
	return (weapon != INVALID_ENT_REFERENCE);
}

/*
 * Checks whether the entity is a valid weapon or not.
 * 
 * @param weapon		Weapon Entity.
 * @return				True if the entity is a valid weapon, false otherwise.
 */
stock Weapon_IsValid(weapon)
{
	if (!IsValidEdict(weapon)) {
		return false;
	}

	return Entity_ClassNameMatches(weapon, "weapon_", true);
}

/**
 * Gets the weapon of a client by the weapon's classname.
 *
 * @param client 		Client Index.
 * @param className		Classname of the weapon.
 * @return				Entity index on success or INVALID_ENT_REFERENCE.
 */
stock Client_GetWeapon(client, const String:className[])
{
	new offset = Client_GetWeaponsOffset(client) - 4;

	for (new i=0; i < MAX_WEAPONS; i++) {
		offset += 4;

		new weapon = GetEntDataEnt2(client, offset);
		
		if (!Weapon_IsValid(weapon)) {
			continue;
		}
		
		if (Entity_ClassNameMatches(weapon, className)) {
			return weapon;
		}
	}
	
	return INVALID_ENT_REFERENCE;
}

/**
 * Gets the offset for a client's weapon list (m_hMyWeapons).
 * The offset will saved globally for optimization.
 *
 * @param client		Client Index.
 * @return				Weapon list offset or -1 on failure.
 */
stock Client_GetWeaponsOffset(client)
{
	static offset = -1;

	if (offset == -1) {
		//offset = FindDataMapOffs(client, "m_hMyWeapons");
		offset = FindDataMapInfo(client, "m_hMyWeapons");
	}
	
	return offset;
}

/**
 * Checks if an entity matches a specific entity class.
 *
 * @param entity		Entity Index.
 * @param class			Classname String.
 * @return				True if the classname matches, false otherwise.
 */
stock bool:Entity_ClassNameMatches(entity, const String:className[], partialMatch=false)
{
	decl String:entity_className[64];
	Entity_GetClassName(entity, entity_className, sizeof(entity_className));

	if (partialMatch) {
		return (StrContains(entity_className, className) != -1);
	}
	
	return StrEqual(entity_className, className);
}

/**
 * Gets the Classname of an entity.
 * This is like GetEdictClassname(), except it works for ALL
 * entities, not just edicts.
 *
 * @param entity			Entity index.
 * @param buffer			Return/Output buffer.
 * @param size				Max size of buffer.
 * @return					
 */
stock Entity_GetClassName(entity, String:buffer[], size)
{
	GetEntPropString(entity, Prop_Data, "m_iClassname", buffer, size);
	
	if (buffer[0] == '\0') {
		return false;
	}
	
	return true;
}
