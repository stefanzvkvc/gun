%% Copyright (c) 2019, Loïc Hoguin <essen@ninenines.eu>
%%
%% Permission to use, copy, modify, and/or distribute this software for any
%% purpose with or without fee is hereby granted, provided that the above
%% copyright notice and this permission notice appear in all copies.
%%
%% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
%% WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
%% MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
%% ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
%% WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
%% ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
%% OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

-module(raw_SUITE).
-compile(export_all).
-compile(nowarn_export_all).

-import(ct_helper, [doc/1]).
-import(gun_test, [init_origin/3]).
-import(gun_test, [receive_from/1]).

all() ->
	[{group, raw}].

groups() ->
	[{raw, [parallel], ct_helper:all(?MODULE)}].

%% Tests.

direct_raw_tcp(_) ->
	doc("Directly connect to a remote endpoint using the raw protocol over TCP."),
	do_direct_raw(tcp).

direct_raw_tls(_) ->
	doc("Directly connect to a remote endpoint using the raw protocol over TLS."),
	do_direct_raw(tls).

do_direct_raw(OriginTransport) ->
	{ok, OriginPid, OriginPort} = init_origin(OriginTransport, raw, fun do_echo/3),
	{ok, ConnPid} = gun:open("localhost", OriginPort, #{
		transport => OriginTransport,
		protocols => [raw]
	}),
	{ok, raw} = gun:await_up(ConnPid),
	handshake_completed = receive_from(OriginPid),
	%% When we take over the entire connection there is no stream reference.
	gun:data(ConnPid, undefined, nofin, <<"Hello world!">>),
	{data, nofin, <<"Hello world!">>} = gun:await(ConnPid, undefined),
	#{
		transport := OriginTransport,
		protocol := raw,
		origin_scheme := _, %% @todo This should be 'undefined'.
		origin_host := "localhost",
		origin_port := OriginPort,
		intermediaries := []
	} = gun:info(ConnPid),
	gun:close(ConnPid).

socks5_tcp_raw_tcp(_) ->
	doc("Use Socks5 over TCP to connect to a remote endpoint using the raw protocol over TCP."),
	do_socks5_raw(tcp, tcp).

socks5_tcp_raw_tls(_) ->
	doc("Use Socks5 over TCP to connect to a remote endpoint using the raw protocol over TLS."),
	do_socks5_raw(tcp, tls).

socks5_tls_raw_tcp(_) ->
	doc("Use Socks5 over TLS to connect to a remote endpoint using the raw protocol over TCP."),
	do_socks5_raw(tls, tcp).

socks5_tls_raw_tls(_) ->
	doc("Use Socks5 over TLS to connect to a remote endpoint using the raw protocol over TLS."),
	do_socks5_raw(tls, tls).

do_socks5_raw(OriginTransport, ProxyTransport) ->
	{ok, OriginPid, OriginPort} = init_origin(OriginTransport, raw, fun do_echo/3),
	{ok, ProxyPid, ProxyPort} = socks_SUITE:do_proxy_start(ProxyTransport, none),
	{ok, ConnPid} = gun:open("localhost", ProxyPort, #{
		transport => ProxyTransport,
		protocols => [{socks, #{
			host => "localhost",
			port => OriginPort,
			transport => OriginTransport,
			protocols => [raw]
		}}]
	}),
	%% We receive a gun_up and a gun_socks_up.
	{ok, socks} = gun:await_up(ConnPid),
	{ok, raw} = gun:await_up(ConnPid),
	%% The proxy received two packets.
	{auth_methods, 1, [none]} = receive_from(ProxyPid),
	{connect, <<"localhost">>, OriginPort} = receive_from(ProxyPid),
	handshake_completed = receive_from(OriginPid),
	%% When we take over the entire connection there is no stream reference.
	gun:data(ConnPid, undefined, nofin, <<"Hello world!">>),
	{data, nofin, <<"Hello world!">>} = gun:await(ConnPid, undefined),
	#{
		transport := OriginTransport,
		protocol := raw,
		origin_scheme := _, %% @todo This should be 'undefined'.
		origin_host := "localhost",
		origin_port := OriginPort,
		intermediaries := [#{
			type := socks5,
			host := "localhost",
			port := ProxyPort,
			transport := ProxyTransport,
			protocol := socks
	}]} = gun:info(ConnPid),
	gun:close(ConnPid).

connect_tcp_raw_tcp(_) ->
	doc("Use CONNECT over TCP to connect to a remote endpoint using the raw protocol over TCP."),
	do_connect_raw(tcp, tcp).

connect_tcp_raw_tls(_) ->
	doc("Use CONNECT over TCP to connect to a remote endpoint using the raw protocol over TLS."),
	do_connect_raw(tcp, tls).

connect_tls_raw_tcp(_) ->
	doc("Use CONNECT over TLS to connect to a remote endpoint using the raw protocol over TCP."),
	do_connect_raw(tls, tcp).

connect_tls_raw_tls(_) ->
	doc("Use CONNECT over TLS to connect to a remote endpoint using the raw protocol over TLS."),
	do_connect_raw(tls, tls).

do_connect_raw(OriginTransport, ProxyTransport) ->
	{ok, OriginPid, OriginPort} = init_origin(OriginTransport, raw, fun do_echo/3),
	{ok, ProxyPid, ProxyPort} = rfc7231_SUITE:do_proxy_start(ProxyTransport),
	Authority = iolist_to_binary(["localhost:", integer_to_binary(OriginPort)]),
	{ok, ConnPid} = gun:open("localhost", ProxyPort, #{transport => ProxyTransport}),
	{ok, http} = gun:await_up(ConnPid),
	StreamRef = gun:connect(ConnPid, #{
		host => "localhost",
		port => OriginPort,
		transport => OriginTransport,
		protocols => [raw]
	}),
	{request, <<"CONNECT">>, Authority, 'HTTP/1.1', _} = receive_from(ProxyPid),
	{response, fin, 200, _} = gun:await(ConnPid, StreamRef),
	handshake_completed = receive_from(OriginPid),
	%% When we take over the entire connection there is no stream reference.
	gun:data(ConnPid, undefined, nofin, <<"Hello world!">>),
	{data, nofin, <<"Hello world!">>} = gun:await(ConnPid, undefined),
	#{
		transport := OriginTransport,
		protocol := raw,
		origin_scheme := _, %% @todo This should be 'undefined'.
		origin_host := "localhost",
		origin_port := OriginPort,
		intermediaries := [#{
			type := connect,
			host := "localhost",
			port := ProxyPort,
			transport := ProxyTransport,
			protocol := http
	}]} = gun:info(ConnPid),
	gun:close(ConnPid).

http11_upgrade_raw_tcp(_) ->
	doc("Use the HTTP Upgrade mechanism to switch to the raw protocol over TCP."),
	do_http11_upgrade_raw(tcp).

http11_upgrade_raw_tls(_) ->
	doc("Use the HTTP Upgrade mechanism to switch to the raw protocol over TLS."),
	do_http11_upgrade_raw(tls).

do_http11_upgrade_raw(OriginTransport) ->
	{ok, OriginPid, OriginPort} = init_origin(OriginTransport, raw,
		fun (Parent, ClientSocket, ClientTransport) ->
			%% We skip the request and send a 101 response unconditionally.
			{ok, _} = ClientTransport:recv(ClientSocket, 0, 5000),
			ClientTransport:send(ClientSocket,
				"HTTP/1.1 101 Switching Protocols\r\n"
				"Connection: upgrade\r\n"
				"Upgrade: custom/1.0\r\n"
				"\r\n"),
			do_echo(Parent, ClientSocket, ClientTransport)
		end),
	{ok, ConnPid} = gun:open("localhost", OriginPort, #{
		transport => OriginTransport
	}),
	{ok, http} = gun:await_up(ConnPid),
	handshake_completed = receive_from(OriginPid),
	StreamRef = gun:get(ConnPid, "/", #{
		<<"connection">> => <<"upgrade">>,
		<<"upgrade">> => <<"custom/1.0">>
	}),
	{upgrade, [<<"custom/1.0">>], _} = gun:await(ConnPid, StreamRef),
	%% When we take over the entire connection there is no stream reference.
	gun:data(ConnPid, undefined, nofin, <<"Hello world!">>),
	{data, nofin, <<"Hello world!">>} = gun:await(ConnPid, undefined),
	#{
		transport := OriginTransport,
		protocol := raw,
		origin_scheme := _, %% @todo This should be 'undefined'.
		origin_host := "localhost",
		origin_port := OriginPort,
		intermediaries := []
	} = gun:info(ConnPid),
	gun:close(ConnPid).

%% The origin server will echo everything back.

do_echo(Parent, ClientSocket, ClientTransport) ->
	case ClientTransport:recv(ClientSocket, 0, 5000) of
		{ok, Data} ->
			ClientTransport:send(ClientSocket, Data),
			do_echo(Parent, ClientSocket, ClientTransport);
		{error, closed} ->
			ok
	end.
