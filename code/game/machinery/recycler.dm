#define SAFETY_COOLDOWN 100

/obj/machinery/recycler
	name = "recycler"
	desc = "A large crushing machine used to recycle small items inefficiently. There are lights on the side."
	icon = 'icons/obj/recycling.dmi'
	icon_state = "grinder-o0"
	layer = ABOVE_ALL_MOB_LAYER // Overhead
	plane = MOB_PLANE
	density = TRUE
	circuit = /obj/item/circuitboard/machine/recycler
	var/safety_mode = FALSE // Temporarily stops machine if it detects a mob, or upon deconstruction.
	var/icon_name = "grinder-o"
	var/blood = 0
	var/eat_dir = WEST
	var/amount_produced = 50
	var/crush_damage = 1000
	var/eat_victim_items = TRUE
	var/item_recycle_sound = 'sound/items/welder.ogg'

/obj/machinery/recycler/Initialize(mapload)
	AddComponent(/datum/component/butchering/recycler, 1, amount_produced,amount_produced/5)
	AddComponent(/datum/component/material_container, list(/datum/material/iron, /datum/material/glass, /datum/material/silver, /datum/material/plasma, /datum/material/gold, /datum/material/diamond, /datum/material/plastic, /datum/material/uranium, /datum/material/titanium, /datum/material/bluespace), INFINITY, FALSE, null, null, null, TRUE)
	. = ..()
	update_icon()
	req_one_access = get_all_accesses() + get_all_centcom_access()

	var/static/list/loc_connections = list(
		COMSIG_ATOM_ENTERED = PROC_REF(on_entered),
	)
	AddElement(/datum/element/connect_loc, loc_connections)


/obj/machinery/recycler/deconstruct(disassembled = TRUE)
	safety_mode = TRUE //to stop stock parts and circuit from being deleted.
	return ..()

/obj/machinery/recycler/RefreshParts()
	var/amt_made = 0
	var/mat_mod = 0
	for(var/obj/item/stock_parts/matter_bin/B in component_parts)
		mat_mod = 2 * B.rating
	mat_mod *= 50000
	for(var/obj/item/stock_parts/manipulator/M in component_parts)
		amt_made = 12.5 * M.rating //% of materials salvaged
	var/datum/component/material_container/materials = GetComponent(/datum/component/material_container)
	materials.max_amount = mat_mod
	amount_produced = min(50, amt_made) + 50
	var/datum/component/butchering/butchering = GetComponent(/datum/component/butchering/recycler)
	butchering.effectiveness = amount_produced
	butchering.bonus_modifier = amount_produced/5

/obj/machinery/recycler/examine(mob/user)
	. = ..()
	. += "<span class='notice'>Reclaiming <b>[amount_produced]%</b> of materials salvaged.</span>"
	. += {"The power light is [(stat & NOPOWER) ? "off" : "on"].
	The safety-mode light is [safety_mode ? "on" : "off"].
	The safety-sensors status light is [obj_flags & EMAGGED ? "off" : "on"]."}

/obj/machinery/recycler/power_change()
	..()
	update_icon()


/obj/machinery/recycler/attackby(obj/item/I, mob/user, params)
	if(default_deconstruction_screwdriver(user, "grinder-oOpen", "grinder-o0", I))
		return

	if(default_pry_open(I))
		return

	if(default_unfasten_wrench(user, I))
		return

	if(default_deconstruction_crowbar(I))
		return
	return ..()

/obj/machinery/recycler/emag_act(mob/user)
	. = ..()
	if(obj_flags & EMAGGED)
		return
	obj_flags |= EMAGGED
	if(safety_mode)
		safety_mode = FALSE
		update_icon()
	playsound(src, "sparks", 75, 1, -1)
	to_chat(user, "<span class='notice'>You use the cryptographic sequencer on [src].</span>")
	return TRUE

/obj/machinery/recycler/update_icon_state()
	var/is_powered = !(stat & (BROKEN|NOPOWER))
	if(safety_mode)
		is_powered = FALSE
	icon_state = icon_name + "[is_powered]" + "[(blood ? "bld" : "")]" // add the blood tag at the end

/obj/machinery/recycler/CanAllowThrough(atom/movable/AM)
	. = ..()
	if(!anchored)
		return

	var/move_dir = get_dir(loc, AM.loc)
	if(move_dir == eat_dir)
		return TRUE

/obj/machinery/recycler/proc/on_entered(datum/source, atom/movable/AM)
	SIGNAL_HANDLER
	INVOKE_ASYNC(src, PROC_REF(eat), AM)

/obj/machinery/recycler/proc/eat(atom/AM0)
	if(stat & (BROKEN|NOPOWER) || safety_mode)
		return

	if(isturf(AM0))
		return

	var/list/to_eat

	to_eat = list(AM0)

	var/items_recycled = 0
	var/buzz = FALSE
	for(var/i in to_eat)
		var/atom/movable/AM = i
		if(QDELETED(AM))
			continue
		var/obj/item/bodypart/head/as_head = AM
		var/obj/item/mmi/as_mmi = AM
		var/brain_holder = istype(AM, /obj/item/organ/brain) || (istype(as_head) && as_head.brain) || (istype(as_mmi) && as_mmi.brain) || istype(AM, /obj/item/dullahan_relay)
		if(brain_holder)
			if(obj_flags & EMAGGED)
				continue
			else
				emergency_stop(AM)
				return
		else if(isliving(AM))
			if((obj_flags & EMAGGED)||((!allowed(AM))&&(!ishuman(AM))))
				to_eat += crush_living(AM)
			else
				emergency_stop(AM)
				return
		else if(isitem(AM))
			var/obj/O = AM
			if(O.resistance_flags & INDESTRUCTIBLE)
				buzz = TRUE
				O.forceMove(loc)
			else
				to_eat += recycle_item(AM)
				items_recycled++
		else
			buzz = TRUE
			AM.forceMove(loc)

	if(items_recycled)
		playsound(src, item_recycle_sound, 50, 1)
	if(buzz)
		playsound(src, 'sound/machines/buzz-sigh.ogg', 50, 0)

/obj/machinery/recycler/proc/recycle_item(obj/item/I)

	. = list()
	for(var/A in I)
		var/atom/movable/AM = A
		AM.forceMove(loc)
		if(AM.loc == loc)
			. += AM

	I.forceMove(loc)
	var/obj/item/grown/log/L = I
	if(istype(L))
		var/seed_modifier = 0
		if(L.seed)
			seed_modifier = round(L.seed.potency / 25)
		new L.plank_type(src.loc, 1 + seed_modifier)
		qdel(L)
		return
	else
		var/datum/component/material_container/materials = GetComponent(/datum/component/material_container)
		var/material_amount = materials.get_item_material_amount(I)
		if(!material_amount)
			qdel(I)
			return
		materials.insert_item(I, multiplier = (amount_produced / 100))
		qdel(I)
		materials.retrieve_all()


/obj/machinery/recycler/proc/emergency_stop(mob/living/L)
	playsound(src, 'sound/machines/buzz-sigh.ogg', 50, 0)
	safety_mode = TRUE
	update_icon()
	L.forceMove(loc)
	addtimer(CALLBACK(src, PROC_REF(reboot)), SAFETY_COOLDOWN)

/obj/machinery/recycler/proc/reboot()
	playsound(src, 'sound/machines/ping.ogg', 50, 0)
	safety_mode = FALSE
	update_icon()

/obj/machinery/recycler/proc/crush_living(mob/living/L)

	. = list()
	L.forceMove(loc)

	if(issilicon(L))
		playsound(src, 'sound/items/welder.ogg', 50, 1)
	else
		playsound(src, 'sound/effects/splat.ogg', 50, 1)

	// By default, the emagged recycler will gib all non-carbons. (human simple animal mobs don't count)
	if(iscarbon(L))
		if(L.stat == CONSCIOUS)
			L.say("ARRRRRRRRRRRGH!!!", forced="recycler grinding")
		add_mob_blood(L)

	if(!blood && !issilicon(L))
		blood = TRUE
		update_icon()

	// Remove and recycle the equipped items
	if(eat_victim_items)
		for(var/obj/item/I in L.get_equipped_items(TRUE))
			if(L.dropItemToGround(I))
				. += I

	// Instantly lie down, also go unconscious from the pain, before you die.
	L.Unconscious(100)
	L.adjustBruteLoss(crush_damage)

/obj/machinery/recycler/deathtrap
	name = "dangerous old crusher"
	obj_flags = CAN_BE_HIT | EMAGGED
	crush_damage = 120
	flags_1 = NODECONSTRUCT_1

/obj/item/paper/guides/recycler
	name = "paper - 'garbage duty instructions'"
	info = "_New Assignment_\n\n You have been assigned to collect garbage from trash bins, located around the station. The crewmembers will put their trash into it and you will collect the said trash.<br><br>There is a recycling machine near your closet, inside maintenance; use it to recycle the trash for a small chance to get useful minerals. Then deliver these minerals to cargo or engineering. You are our last hope for a clean station, do not screw this up!"

#undef SAFETY_COOLDOWN
