class_name SiRecordingClient
extends SiClient
## Records sent actions instead of writing to a socket.

var sent: Array[SiAction] = []


func send_act(action: SiAction) -> int:
	sent.append(action)
	return sent.size()
