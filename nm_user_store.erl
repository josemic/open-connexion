-module(nm_user_store).

-export([init/0,create_user/4,check_password/2, is_user_attached/1, get_pid/1, get_udpProcessPid/1,get_ref/1, user_exists/1, get_user_record/1,
	 delete_by_username/1, delete_by_pid/1,get_user_record_by_ref/1,get_username_by_ref/1,get_pid_by_ref/1, get_udp_process_pid_by_ref/1]).

-define(TABLE_ID, ?MODULE).

-record(user,{username,password,pid,udpProcessPid,ref}). 


init() ->
    ets:new(?TABLE_ID, [public, named_table, {keypos,#user.username}]),
    ok.

create_user(Username, Password, Pid, UdpProcessPid) ->
    UserReference = make_ref(),
    ets:insert(?TABLE_ID,#user{username = Username, password= Password, pid= Pid, udpProcessPid = UdpProcessPid, ref= UserReference }).

check_password(Username, Password) ->
    {ok, User_record} = get_user_record(Username),
    if 
	User_record#user.password == Password -> ok;
	true -> {error, incorrectPassword}  % else clause
    end.

is_user_attached(Username) ->
    case get_user_record(Username) of
	{ok, _} -> true;
	{error, userIsNotAvailable} -> false
    end.

get_pid(Username) ->
    case get_user_record(Username) of 
	{ok, User_record} -> {ok, User_record#user.pid};
	{error, userIsNotAvailable} -> {error, pidIsNotAvailable}
    end.

get_udpProcessPid(Username) ->
    case get_user_record(Username) of 
	{ok, User_record} -> {ok, User_record#user.udpProcessPid};
	{error, userIsNotAvailable} -> {error, pidIsNotAvailable}
    end.

get_ref(Username) ->
    case get_user_record(Username) of 
	{ok, User_record} -> {ok, User_record#user.ref};
	{error, userIsNotAvailable} -> {error, refIsNotAvailable}
    end.

user_exists(Username) ->
    case get_user_record(Username) of 
	{ok, _User_record} -> {ok, userIsAvailable};
	{error, userIsNotAvailable} -> {error, userIsNotAvailable}
    end.

get_user_record(Username) -> 
    UserRecordList= ets:lookup(?TABLE_ID,Username),
    case UserRecordList of
	[User_record] -> {ok, User_record};
	[] -> {error, userIsNotAvailable}
    end.

delete_by_username(Username) ->
    ets:match_delete(?TABLE_ID,#user{username=Username, _ = '_' }).

delete_by_pid(Pid) ->
    ets:match_delete(?TABLE_ID,#user{pid=Pid, _ = '_' }).

get_user_record_by_ref(Ref) ->
    ets:match_object(?TABLE_ID,#user{ref=Ref, _ = '_' }).

get_username_by_ref(Ref) ->
    case get_user_record_by_ref(Ref) of 
	[User_record|_] -> {ok, User_record#user.username};
	[] -> {error, unknownReference}
    end.

get_pid_by_ref(Ref) ->
    case get_user_record_by_ref(Ref) of 
        [User_record|_] -> {ok, User_record#user.pid};
	{error, userIsNotAvailable} -> {error, unknownReference};
	[]-> {error, unknownReference}
    end.

get_udp_process_pid_by_ref(Ref) ->
    case get_user_record_by_ref(Ref) of 
        [User_record|_] -> {ok, User_record#user.udpProcessPid};
	{error, userIsNotAvailable} -> {error, unknownReference};
	[] ->  {error, unknownReference}	       
    end.
