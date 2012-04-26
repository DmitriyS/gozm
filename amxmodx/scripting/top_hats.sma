/* 
���� �������
������ �������� ������� �� �������� ��� ���� �� 4 �� 15
� ��� �� 1 �� 3 - ���� ���������

������ 0.1
����� - �
������
<amxmodx> 
<fakemeta> 
<hamsandwich> 
<csstats>

� ��������� 13 � 14 �������
new MODEL_TOP15[] = "models/pp_top15.mdl"
new MODEL_TOP3[] = "models/pp_top3.mdl"

��� �� ������ ��������� ���� ������ ���� ��� �� �������� ��,��� ������ �.

�������: xPaw �� ��� ������ SantaHats & sgtbane �� �������� �����
*/

#include <amxmodx> 
#include <fakemeta> 
#include <hamsandwich> 
#include <csstats>

#define PLUGIN "TOP Hats"
#define VERSION "0.1"
#define AUTHOR "TTuCTOH"

new g_topEnt[33]
new MODEL_TOP15[] = "models/jamacahat2.mdl"
new MODEL_TOP3[] = "models/pp_top3.mdl"
new g_CachedStringInfoTarget

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR)
	
	RegisterHam(Ham_Spawn, "player", "fwHamPlayerSpawnPost", 1);
	g_CachedStringInfoTarget = engfunc( EngFunc_AllocString, "info_target" );
}

public plugin_precache()
{
	precache_model(MODEL_TOP15)
	precache_model(MODEL_TOP3)
}

public fwHamPlayerSpawnPost(id) 
{
	new stats[8], bodyhits[8]
	new iRank;
 	iRank = get_user_stats(id, stats, bodyhits)
	
	if(1 <= iRank <= 3)
	{
		if(is_user_alive(id))
		{
			new iEnt = g_topEnt[id]
			if( !pev_valid(iEnt))
			{
				g_topEnt[id] = iEnt = engfunc(EngFunc_CreateNamedEntity, g_CachedStringInfoTarget)
				set_pev(iEnt, pev_movetype, MOVETYPE_FOLLOW)
				set_pev(iEnt, pev_aiment, id)
				engfunc(EngFunc_SetModel, iEnt, MODEL_TOP3)
			}
		}
	}
	if(4 <= iRank <= 15)
	{
		if(is_user_alive(id))
		{
			new iEnt = g_topEnt[id]
			if( !pev_valid(iEnt))
			{
				g_topEnt[id] = iEnt = engfunc(EngFunc_CreateNamedEntity, g_CachedStringInfoTarget)
				set_pev(iEnt, pev_movetype, MOVETYPE_FOLLOW)
				set_pev(iEnt, pev_aiment, id)
				engfunc(EngFunc_SetModel, iEnt, MODEL_TOP15)
			}
		}
	}
	else
	{
		return PLUGIN_HANDLED
	}
	return PLUGIN_CONTINUE
}