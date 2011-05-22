-module(nm_messages).
-compile(export_all).
-include("nm_message_types.hrl").



attach_resp() ->
    <<?ATTACH_RESP:16>>.

setup_resp() ->
    <<?SETUP_RESP:16>>.

attach_rej(alreadyAttachedError) ->
    attach_rej(?ALREADY_ATTACHED_ERROR);

attach_rej(ErrorReason) when is_integer(ErrorReason)->
    <<?ATTACH_REJ:16, ErrorReason:16>>.

setup_rej(notAttachedError) ->
    setup_rej(?NOT_ATTACHED_ERROR);

setup_rej(peerNotAttachedError) ->
    setup_rej(?PEER_NOT_ATTACHED_ERROR);

setup_rej(passwordIncorrectError) ->
    setup_rej(?PASSWORD_INCORRECT_ERROR);

setup_rej(pidIsNotAvailableError) ->
    setup_rej(?PID_IS_NOT_AVAILABLE_ERROR);

setup_rej(peerIsDetachedError) ->
    setup_rej(?PEER_IS_DETACHED_ERROR);

setup_rej(alreadySetupError) ->
    setup_rej(?ALREADY_SETUP_ERROR);

setup_rej(ErrorReason) when is_integer(ErrorReason)->
    <<?SETUP_REJ:16, ErrorReason:16>>.

release_rej(notConnectedError) ->
    release_rej(?NOT_CONNECTED_ERROR);

release_rej(ErrorReason) when is_integer(ErrorReason)->
    <<?RELEASE_REJ:16, ErrorReason:16>>.


attach_req(Username, Password) ->
    UsernameSize = size(Username),
    PasswordSize = size(Password),
    <<?ATTACH_REQ:16, UsernameSize:8,Username/binary, PasswordSize:8, Password/binary>>.

setup_req(PeerUsername, PeerUserPassword)->
    PeerUsernameSize = size(PeerUsername),
    PeerUserPasswordSize = size(PeerUserPassword),
    <<?SETUP_REQ:16, PeerUsernameSize:8,PeerUsername/binary, PeerUserPasswordSize:8, PeerUserPassword/binary>>.

release_req()->
    <<?RELEASE_REQ:16>>.

release_resp()->
    <<?RELEASE_RESP:16>>.

link_start_ind(Ref)->
    RefBin = term_to_binary(Ref),
    <<?LINK_START_IND:16, RefBin:33/binary-unit:8>>.

link_stop_ind() ->
    <<?LINK_STOP_IND:16>>.

punch_start_ind(ToIP, ToPort)->
    {IP1,IP2,IP3,IP4}=ToIP,
    <<?PUNCH_START_IND:16, IP1:16,IP2:16,IP3:16,IP4:16,ToPort:16>>.

punch_stop_ind() ->
    <<?PUNCH_STOP_IND:16>>.

keep_alive_ind() ->
    <<?KEEP_ALIVE_IND:16>>.

udp_port_info_ind(BinRef, ClientUDPPort) ->
    <<?UDP_PORT_INFO_IND:16, BinRef:33/binary, ClientUDPPort:16>>.

udp_peer2peer_ind(BinRef, ClientUDPPort) ->
    <<?UDP_PEER2PEER_IND:16, BinRef:33/binary-unit:8, ClientUDPPort:16>>.

udp_peer2peer_pushback_ind(BinRef, ClientUDPPort) ->
    <<?UDP_PEER2PEER_PUSHBACK_IND:16, BinRef:33/binary-unit:8, ClientUDPPort:16>>.

