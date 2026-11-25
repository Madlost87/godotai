extends RefCounted
## Riceve i pacchetti JSON del tracker su UDP (solo localhost).

var port: int = 0

var _peer: PacketPeerUDP = PacketPeerUDP.new()
var _json: JSON = JSON.new()


func listen(p: int) -> bool:
	close()
	var err := _peer.bind(p, "127.0.0.1")
	if err != OK:
		push_warning("BodyInput: impossibile ascoltare sulla porta UDP %d (errore %d)" % [p, err])
		return false
	port = p
	return true


func close() -> void:
	if _peer.is_bound():
		_peer.close()
	port = 0


## Tutti i pacchetti JSON validi arrivati dall'ultima chiamata, in ordine.
func poll() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _peer.is_bound():
		return out
	while _peer.get_available_packet_count() > 0:
		var text := _peer.get_packet().get_string_from_utf8()
		if _json.parse(text) == OK and _json.data is Dictionary:
			out.append(_json.data)
	return out
