%%% TCP messages
-define(ATTACH_REQ, 16#0).
-define(ATTACH_RESP, 16#1).
-define(ATTACH_REJ, 16#2).


-define(DETACH_REQ, 16#3).
-define(SETUP_REQ, 16#4).
-define(SETUP_RESP, 16#5).
-define(SETUP_REJ, 16#6).

-define(RELEASE_REQ, 16#20).
-define(RELEASE_RESP, 16#21).
-define(RELEASE_REJ, 16#22).

-define(LINK_START_IND, 16#30).
-define(LINK_STOP_IND, 16#31).

-define(PUNCH_START_IND, 16#40).
-define(PUNCH_STOP_IND, 16#41).

-define(KEEP_ALIVE_IND, 16#50).

%%% UDP messages
-define(UDP_PORT_INFO_IND, 16#80). 
-define(UDP_PEER2PEER_IND, 16#81).
-define(UDP_PEER2PEER_PUSHBACK_IND, 16#82).

%%% Error reasons:
-define(ALREADY_ATTACHED_ERROR, 16#0).
-define(NOT_ATTACHED_ERROR, 16#1).
-define(PEER_NOT_ATTACHED_ERROR, 16#2).
-define(PASSWORD_INCORRECT_ERROR, 16#3).
-define(PID_IS_NOT_AVAILABLE_ERROR, 16#4).
-define(PEER_IS_DETACHED_ERROR, 16#5).
-define(ALREADY_SETUP_ERROR, 16#6).
-define(NOT_CONNECTED_ERROR, 16#7).
