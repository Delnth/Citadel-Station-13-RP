#define AIRLOCK_CONTROL_RANGE 22

// This code allows for airlocks to be controlled externally by setting an id_tag and comm frequency (disables ID access)
/obj/machinery/door/airlock
	var/id_tag
	var/frequency
	var/shockedby = list()
	var/datum/radio_frequency/radio_connection
	var/cur_command = null	//the command the door is currently attempting to complete

/obj/machinery/door/airlock/process(delta_time)
	if (..() == PROCESS_KILL && !cur_command)
		. = PROCESS_KILL
	if (arePowerSystemsOn())
		execute_current_command()

/obj/machinery/door/airlock/receive_signal(datum/signal/signal)
	if (!arePowerSystemsOn()) return //no power

	if(!signal || signal.encryption) return

	if(id_tag != signal.data["tag"] || !signal.data["command"]) return

	cur_command = signal.data["command"]
	execute_current_command()
	if(cur_command)
		START_MACHINE_PROCESSING(src)


/obj/machinery/door/airlock/proc/execute_current_command()
	if(operating)
		return //emagged or busy doing something else

	if (!cur_command)
		return

	spawn()
		do_command(cur_command)
		if (command_completed(cur_command))
			cur_command = null

/obj/machinery/door/airlock/proc/do_command(command)
	switch(command)
		if("open")
			open()

		if("close")
			close()

		if("unlock")
			unlock()

		if("lock")
			lock()

		if("secure_open")
			unlock()

			sleep(2)
			open()

			lock()

		if("secure_close")
			unlock()
			close()

			lock()
			sleep(2)

	send_status()

/obj/machinery/door/airlock/proc/command_completed(command)
	switch(command)
		if("open")
			return (!density)

		if("close")
			return density

		if("unlock")
			return !locked

		if("lock")
			return locked

		if("secure_open")
			return (locked && !density)

		if("secure_close")
			return (locked && density)

	return 1	//Unknown command. Just assume it's completed.

/obj/machinery/door/airlock/proc/send_status(bumped = 0)
	if(radio_connection)
		var/datum/signal/signal = new
		signal.transmission_method = TRANSMISSION_RADIO //radio signal
		signal.data["tag"] = id_tag
		signal.data["timestamp"] = world.time

		signal.data["door_status"] = density?("closed"):("open")
		signal.data["lock_status"] = locked?("locked"):("unlocked")

		if (bumped)
			signal.data["bumped_with_access"] = 1

		radio_connection.post_signal(src, signal, range = AIRLOCK_CONTROL_RANGE, radio_filter = RADIO_AIRLOCK)


/obj/machinery/door/airlock/open(surpress_send)
	. = ..()
	if(!surpress_send) send_status()


/obj/machinery/door/airlock/close(surpress_send)
	. = ..()
	if(!surpress_send) send_status()


/obj/machinery/door/airlock/Bumped(atom/AM)
	..(AM)
	if(istype(AM, /obj/mecha))
		var/obj/mecha/mecha = AM
		if(density && radio_connection && mecha.occupant && (src.allowed(mecha.occupant) || src.check_access_list(mecha.operation_req_access)))
			send_status(1)
	return

/obj/machinery/door/airlock/proc/set_frequency(new_frequency)
	radio_controller.remove_object(src, frequency)
	if(new_frequency)
		frequency = new_frequency
		radio_connection = radio_controller.add_object(src, frequency, RADIO_AIRLOCK)


/obj/machinery/door/airlock/Initialize()
	. = ..()
	if(frequency)
		set_frequency(frequency)

	update_icon()

/obj/machinery/door/airlock/Destroy()
	if(frequency && radio_controller)
		radio_controller.remove_object(src,frequency)
	return ..()

/obj/machinery/airlock_sensor
	icon = 'icons/obj/airlock_machines.dmi'
	icon_state = "airlock_sensor_off"
	name = "airlock sensor"
	desc = "Sends atmospheric readings to a nearby controller."

	anchored = 1
	power_channel = ENVIRON

	var/id_tag
	var/master_tag
	var/frequency = 1379
	var/command = "cycle"

	var/datum/radio_frequency/radio_connection

	var/on = 1
	var/alert = 0
	var/previous_pressure
	var/previous_phoron
	var/previous_temperature

/obj/machinery/airlock_sensor/update_icon()
	if(on)
		if(alert)
			icon_state = "airlock_sensor_alert"
		else
			icon_state = "airlock_sensor_standby"
	else
		icon_state = "airlock_sensor_off"

/obj/machinery/airlock_sensor/attack_hand(mob/user, list/params)
	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO //radio signal
	signal.data["tag"] = master_tag
	signal.data["command"] = command

	radio_connection.post_signal(src, signal, range = AIRLOCK_CONTROL_RANGE, radio_filter = RADIO_AIRLOCK)
	flick("airlock_sensor_cycle", src)

// Checks the change of the values, if the change is sufficently large on any of them, send a new signal
/obj/machinery/airlock_sensor/proc/delta_check(var/new_pressure, var/new_phoron, var/new_temperature)
	if(previous_pressure == null || previous_phoron == null || previous_temperature == null)
		return 1
	if(abs(new_pressure - previous_pressure) > 0.1)
		return 1
	if(abs(new_phoron - previous_phoron) > 0.1)
		return 1
	if(abs(previous_temperature - previous_temperature) > 0.1)
		return 1
	return 0

/obj/machinery/airlock_sensor/process(delta_time)
	if(on)
		var/datum/gas_mixture/air_sample = return_air()
		var/pressure = round(air_sample.return_pressure(),0.1)
		var/phoron = (GAS_ID_PHORON in air_sample.gas) ? round(air_sample.gas[GAS_ID_PHORON], 0.1) : 0
		var/temperature = round(air_sample.temperature, 0.1)

		if(delta_check(pressure, phoron, temperature))
			var/datum/signal/signal = new
			signal.transmission_method = TRANSMISSION_RADIO //radio signal
			signal.data["tag"] = id_tag
			signal.data["timestamp"] = world.time
			signal.data["pressure"] = num2text(pressure)
			signal.data["phoron"] = num2text(phoron)
			signal.data["temperature"] = num2text(temperature)

			radio_connection.post_signal(src, signal, range = AIRLOCK_CONTROL_RANGE, radio_filter = RADIO_AIRLOCK)

			previous_pressure = pressure
			previous_phoron = phoron
			previous_temperature = temperature

			alert = (pressure < ONE_ATMOSPHERE*0.8)

			update_icon()

/obj/machinery/airlock_sensor/proc/set_frequency(new_frequency)
	radio_controller.remove_object(src, frequency)
	frequency = new_frequency
	radio_connection = radio_controller.add_object(src, frequency, RADIO_AIRLOCK)

/obj/machinery/airlock_sensor/Initialize()
	. = ..()
	set_frequency(frequency)

/obj/machinery/airlock_sensor/Destroy()
	if(radio_controller)
		radio_controller.remove_object(src,frequency)
	return ..()

/obj/machinery/airlock_sensor/airlock_interior
	command = "cycle_interior"

/obj/machinery/airlock_sensor/airlock_exterior
	command = "cycle_exterior"

// Return the air from the turf in "front" of us (Used in shuttles, so it can be in the shuttle area but sense outside it)
/obj/machinery/airlock_sensor/airlock_exterior/shuttle/return_air()
	var/turf/T = get_step(src, dir)
	if(isnull(T))
		return ..()
	return T.return_air()

/obj/machinery/access_button
	icon = 'icons/obj/airlock_machines.dmi'
	icon_state = "access_button_standby"
	name = "access button"

	anchored = 1
	power_channel = ENVIRON

	var/master_tag
	var/frequency = 1449
	var/command = "cycle"

	var/datum/radio_frequency/radio_connection

	var/on = 1


/obj/machinery/access_button/update_icon()
	if(on)
		icon_state = "access_button_standby"
	else
		icon_state = "access_button_off"

/obj/machinery/access_button/attackby(obj/item/I as obj, mob/user as mob)
	//Swiping ID on the access button
	if (istype(I, /obj/item/card/id) || istype(I, /obj/item/pda))
		attack_hand(user)
		return
	..()

/obj/machinery/access_button/attack_hand(mob/user, list/params)
	..()
	if(!allowed(user))
		to_chat(user, "<span class='warning'>Access Denied</span>")

	else if(radio_connection)
		var/datum/signal/signal = new
		signal.transmission_method = TRANSMISSION_RADIO //radio signal
		signal.data["tag"] = master_tag
		signal.data["command"] = command

		radio_connection.post_signal(src, signal, range = AIRLOCK_CONTROL_RANGE, radio_filter = RADIO_AIRLOCK)
	flick("access_button_cycle", src)


/obj/machinery/access_button/proc/set_frequency(new_frequency)
	radio_controller.remove_object(src, frequency)
	frequency = new_frequency
	radio_connection = radio_controller.add_object(src, frequency, RADIO_AIRLOCK)


/obj/machinery/access_button/Initialize()
	. = ..()
	set_frequency(frequency)

/obj/machinery/access_button/Destroy()
	if(radio_controller)
		radio_controller.remove_object(src, frequency)
	return ..()

/obj/machinery/access_button/airlock_interior
	frequency = 1379
	command = "cycle_interior"

/obj/machinery/access_button/airlock_exterior
	frequency = 1379
	command = "cycle_exterior"
