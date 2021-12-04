/*
*	Shove Penalty Unlocker
*	Copyright (C) 2021 Silvers
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



#define PLUGIN_VERSION 		"1.2"

/*=======================================================================================
	Plugin Info:

*	Name	:	[L4D] Shove Penalty Unlocker
*	Author	:	SilverShot
*	Descrp	:	Unlocks shove penalty in coop and survival.
*	Link	:	https://forums.alliedmods.net/showthread.php?t=319505
*	Plugins	:	https://sourcemod.net/plugins.php?exact=exact&sortby=title&search=1&author=Silvers

========================================================================================
	Change Log:

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

int g_ByteCount, g_ByteSaved[MAX_COUNT];
Address g_Address;



// ====================================================================================================
//					PLUGIN
// ====================================================================================================
public Plugin myinfo =
{
	name = "[L4D] Shove Penalty Unlocker",
	author = "SilverShot",
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

	if( g_ByteSaved[0] != 0xE8 ) SetFailState("Failed to load, byte mis-match. %d (0x%02X != 0xE8)", offset, g_ByteSaved[0]);

	delete hGameData;

	PatchAddress(true);

	CreateConVar("l4d_shove_penalty_version", PLUGIN_VERSION, "Shove Penalty Unlocker plugin version.", FCVAR_NOTIFY|FCVAR_DONTRECORD);
}

public void OnPluginEnd()
{
	PatchAddress(false);
}

void PatchAddress(bool patch)
{
	static bool patched;

	if( !patched && patch )
	{
		patched = true;
		for( int i = 0; i < g_ByteCount; i++ )
			StoreToAddress(g_Address + view_as<Address>(i), 0x90, NumberType_Int8);
	}
	else if( patched && !patch )
	{
		patched = false;
		for( int i = 0; i < g_ByteCount; i++ )
			StoreToAddress(g_Address + view_as<Address>(i), g_ByteSaved[i], NumberType_Int8);
	}
}