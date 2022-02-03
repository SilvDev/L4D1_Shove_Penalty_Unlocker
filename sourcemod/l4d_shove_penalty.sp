/*
*	Shove Penalty Unlocker
*	Copyright (C) 2022 Silvers
*
*	This program is free software: you can redistribute it and/or modify
*	it under the terms of the GNU General Public License as published by
*	the Free Software Foundation, either version 3 of the License, or
*	(at your option) any later version.
*
*	This program is distributed in the hope that it will be useful,
*	but WITHOUT ANY WARRANTY; without even the implied warranty of
*	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
*	GNU General Public License for more details.
*
*	You should have received a copy of the GNU General Public License
*	along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/



#define PLUGIN_VERSION 		"1.3"

/*=======================================================================================
	Plugin Info:

*	Name	:	[L4D] Shove Penalty Unlocker
*	Author	:	SilverShot
*	Descrp	:	Unlocks shove penalty in coop and survival.
*	Link	:	https://forums.alliedmods.net/showthread.php?t=319505
*	Plugins	:	https://sourcemod.net/plugins.php?exact=exact&sortby=title&search=1&author=Silvers

========================================================================================
	Change Log:

1.3 (03-Jan-2022)
	- Added cvar "z_gun_swing_coop_penalty_time" to set the number of swings before melee fatigue delay. Thanks to "HarryPotter" for writing.
	- Changes to work with the latest Linux update. Thanks to "HarryPotter" for testing.
	- Plugin and GameData updated.

1.2a (06-Dec-2021)
	- GameData update: Changed patch count to fix crashing. Thanks to "ZBzibing" for reporting.

1.2 (07-Sep-2021)
	- GameData update: Fixed crashing since the last L4D1 update.

1.1 (10-May-2020)
	- Added better error log message when gamedata file is missing.
	- Various changes to tidy up code.

1.0 (04-Nov-2019)
	- Initial release.

======================================================================================*/

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define GAMEDATA			"l4d_shove_penalty"
#define MAX_COUNT			26
#define MAX_EXISTING_FATIGUE 3

int g_ByteCount, g_ByteSaved[MAX_COUNT];
Address g_Address;

ConVar g_hTimePenalty, g_hCvarMPGameMode;
int g_iTimePenalty;
bool g_bCvarAllow, g_bMapStarted;



// ====================================================================================================
//					PLUGIN
// ====================================================================================================
public Plugin myinfo =
{
	name = "[L4D] Shove Penalty Unlocker",
	author = "SilverShot & HarryPotter",
	description = "Unlocks shove penalty in coop and survival.",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=319505"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion test = GetEngineVersion();
	if( test != Engine_Left4Dead )
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 1.");
		return APLRes_SilentFailure;
	}
	return APLRes_Success;
}

public void OnPluginStart()
{
	// GameData
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "gamedata/%s.txt", GAMEDATA);
	if( FileExists(sPath) == false ) SetFailState("\n==========\nMissing required file: \"%s\".\nRead installation instructions again.\n==========", sPath);

	Handle hGameData = LoadGameConfigFile(GAMEDATA);
	if( hGameData == null ) SetFailState("Failed to load \"%s.txt\" gamedata.", GAMEDATA);

	g_Address = GameConfGetAddress(hGameData, "CTerrorWeapon::TrySwing");
	if( !g_Address ) SetFailState("Failed to load \"CTerrorWeapon::TrySwing\" address.");

	int offset = GameConfGetOffset(hGameData, "TrySwing_Offset");
	if( offset == -1 ) SetFailState("Failed to load \"TrySwing_Offset\" offset.");

	g_ByteCount = GameConfGetOffset(hGameData, "TrySwing_Count");
	if( g_ByteCount == -1 ) SetFailState("Failed to load \"TrySwing_Count\" count.");
	if( g_ByteCount > MAX_COUNT ) SetFailState("Error: byte count exceeds scripts defined value (%d/%d).", g_ByteCount, MAX_COUNT);

	g_Address += view_as<Address>(offset);

	for( int i = 0; i < g_ByteCount; i++ )
	{
		g_ByteSaved[i] = LoadFromAddress(g_Address + view_as<Address>(i), NumberType_Int8);
	}

	if( g_ByteSaved[0] != (g_ByteCount == 1 ? 0x0F : 0xE8) ) SetFailState("Failed to load, byte mis-match. %d (0x%02X != 0xE8)", offset, g_ByteSaved[0]);

	delete hGameData;



	// Cvars
	CreateConVar("l4d_shove_penalty_version", PLUGIN_VERSION, "Shove Penalty Unlocker plugin version.", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	g_hTimePenalty = CreateConVar("z_gun_swing_coop_penalty_time", "5", "The number of swings before the punch/melee/shove fatigue delay is set in (coop). (Min: 2, Max: 5, default: 5).", FCVAR_NOTIFY, true, 2.0, true, 5.0);
	AutoExecConfig(true, "l4d_shove_penalty");

	GetCvars();
	g_hCvarMPGameMode = FindConVar("mp_gamemode");
	g_hCvarMPGameMode.AddChangeHook(ConVarGameMode);
	g_hTimePenalty.AddChangeHook(ConVarChanged_Cvars);
}

public void OnPluginEnd()
{
	PatchAddress(false);
}



// ====================================================================================================
//					CVARS
// ====================================================================================================
public void OnMapStart()
{
	g_bMapStarted = true;
}

public void OnMapEnd()
{
	g_bMapStarted = false;
}

public void OnConfigsExecuted()
{
	IsAllowed();
}

public void ConVarGameMode(ConVar convar, const char[] oldValue, const char[] newValue)
{
	IsAllowed();
}

void IsAllowed()
{
	bool bAllowMode = IsAllowedGameMode();
	GetCvars();

	if( g_bCvarAllow == false && bAllowMode == true )
	{
		g_bCvarAllow = true;
		PatchAddress(true);

		AddNormalSoundHook(HookSound_Callback);
	}

	else if( g_bCvarAllow == true && bAllowMode == false )
	{
		g_bCvarAllow = false;
		PatchAddress(false);

		RemoveNormalSoundHook(HookSound_Callback);
	}
}

int g_iCurrentMode;
bool IsAllowedGameMode()
{
	if( g_bMapStarted == false )
		return false;

	if( g_hCvarMPGameMode == null )
		return false;

	g_iCurrentMode = 0;

	int entity = CreateEntityByName("info_gamemode");
	if( IsValidEntity(entity) )
	{
		DispatchSpawn(entity);
		HookSingleEntityOutput(entity, "OnCoop", OnGamemode, true);
		HookSingleEntityOutput(entity, "OnSurvival", OnGamemode, true);
		HookSingleEntityOutput(entity, "OnVersus", OnGamemode, true);
		HookSingleEntityOutput(entity, "OnScavenge", OnGamemode, true);
		ActivateEntity(entity);
		AcceptEntityInput(entity, "PostSpawnActivate");
		if( IsValidEntity(entity) ) // Because sometimes "PostSpawnActivate" seems to kill the ent.
			RemoveEdict(entity); // Because multiple plugins creating at once, avoid too many duplicate ents in the same frame
	}

	if( g_iCurrentMode == 0 )
		return false;

	if( g_iCurrentMode == 4 )
		return false;

	return true;
}

public void OnGamemode(const char[] output, int caller, int activator, float delay)
{
	if( strcmp(output, "OnCoop") == 0 )
		g_iCurrentMode = 1;
	else if( strcmp(output, "OnSurvival") == 0 )
		g_iCurrentMode = 2;
	else if( strcmp(output, "OnVersus") == 0 )
		g_iCurrentMode = 4;
}

public void ConVarChanged_Cvars(ConVar convar, const char[] oldValue, const char[] newValue)
{
	GetCvars();
}

void GetCvars()
{
	g_iTimePenalty = g_hTimePenalty.IntValue;
}



// ====================================================================================================
//					FATIGUE
// ====================================================================================================

//This hook will be useful for our purpose because there are no events fired when player shoves.
public Action HookSound_Callback(int Clients[64], int &NumClients, char StrSample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
	if( g_iTimePenalty == 5 )
		return Plugin_Continue;

	if( entity <= 0 || entity > MaxClients )
		return Plugin_Continue;

	// Shove detected...
	if( strncmp(StrSample, "player/survivor/swing", 21, false) == -1 )
		return Plugin_Continue;

	if( !IsClientInGame(entity) || GetClientTeam(entity) != 2 )
		return Plugin_Continue;

	int shovePenalty = L4D_GetMeleeFatigue(entity);

	// PrintToChatAll("Current shove penalty: %N - %i", entity, shovePenalty);

	if( shovePenalty < 0 )
		shovePenalty = 0;

	if( MAX_EXISTING_FATIGUE >= shovePenalty && shovePenalty >= g_iTimePenalty - 2 )
	{
		L4D_SetMeleeFatigue(entity, MAX_EXISTING_FATIGUE);
		// PrintToChatAll("Set shove penalty to %i", MAX_EXISTING_FATIGUE);
	}

	return Plugin_Continue;
}

int L4D_GetMeleeFatigue(int client)
{
	return GetEntProp(client, Prop_Send, "m_iShovePenalty", 4);
}

void L4D_SetMeleeFatigue(int client, int value)
{
	SetEntProp(client, Prop_Send, "m_iShovePenalty", value);
}



// ====================================================================================================
//					PATCH
// ====================================================================================================
void PatchAddress(bool patch)
{
	static bool patched;

	if( !patched && patch )
	{
		patched = true;

		// Linux
		if( g_ByteCount == 1 )
		{
			StoreToAddress(g_Address + view_as<Address>(1), 0x89, NumberType_Int8);
		}
		else
		// Windows
		{
			for( int i = 0; i < g_ByteCount; i++ )
				StoreToAddress(g_Address + view_as<Address>(i), 0x90, NumberType_Int8);
		}
	}
	else if( patched && !patch )
	{
		patched = false;
		for( int i = 0; i < g_ByteCount; i++ )
			StoreToAddress(g_Address + view_as<Address>(i), g_ByteSaved[i], NumberType_Int8);
	}
}