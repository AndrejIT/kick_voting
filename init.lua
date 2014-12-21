-- Minetest mod "Kick voting"
-- Allows players to vote to ban someone for limited time/ or to just kick him on each deth/ or move him to jail. I hawe not decided yet.

--This library is free software; you can redistribute it and/or
--modify it under the terms of the GNU Lesser General Public
--License as published by the Free Software Foundation; either
--version 2.1 of the License, or (at your option) any later version.

kick_voting={}
kick_voting.vote_needed=6;  --needed votes
kick_voting.formspec_buffer={}
kick_voting.suspect_by_name={}
kick_voting.suspect_by_ip={}
kick_voting.filename = minetest.get_worldpath() .. "/kick_voting_by_ip.txt"

function kick_voting:save()
    local datastring = minetest.serialize(self.suspect_by_ip)
    if not datastring then
        return
    end
    local file, err = io.open(self.filename, "w")
    if err then
        return
    end
    file:write(datastring)
    file:close()
end

function kick_voting:load()
    local file, err = io.open(self.filename, "r")
    if err then
        self.suspect_by_ip = {}
        return
    end
    self.suspect_by_ip = minetest.deserialize(file:read("*all"))
    if type(self.suspect_by_ip) ~= "table" then
        self.suspect_by_ip = {}
    end
    file:close()
end

-- scenario with loading from file is less tested.
kick_voting:load();

--every restart - decrease vote result
for key, val in pairs(kick_voting.suspect_by_ip) do
    if val.votes > 0 then
        val.votes = val.votes - 1;
    elseif val.votes < 0 then
        val.votes = val.votes + 1;
    end
end

kick_voting.after_place_node = function(pos, placer)
    if placer and placer:is_player() then
        local node = minetest.get_node(pos);
        local meta = minetest.get_meta(pos);
        local description = "Specify player name for voting to kick";
        local player_name = placer:get_player_name();
        meta:set_string("infotext", description);
        meta:set_string("owner", player_name);
        meta:set_string("formspec", "size[6,3;]"
            .."label[0,0;Write player name to vote for kick:]"
            .."field[1,1;3,1;suspect;;]"
            .."button_exit[0,2;2,0.5;save;OK]");
    end
end

kick_voting.receive_config_fields = function(pos, formname, fields, sender)
    local node = minetest.get_node(pos);
    local meta = minetest.get_meta(pos);
    local suspect_name = tostring(fields.suspect);
    local player_name = sender:get_player_name();
    local description = "Vote to kick player <".. suspect_name .."> until the end of the day. Click with gold bar to vote.";
    if fields.suspect and player_name and suspect_name~="" then
        meta:set_string("infotext", description);
        meta:set_string("owner", nil);
        meta:set_string("formspec", nil);
        meta:set_string("suspect", suspect_name);
        kick_voting.register_vote(player_name, suspect_name, pos);
    end
end

kick_voting.on_rightclick = function(pos, node, player, itemstack, pointed_thing)
    local meta = minetest.get_meta(pos);
    local suspect_name = meta:get_string("suspect");
    local player_name = player:get_player_name();
    if itemstack:get_name()=="default:gold_ingot" and suspect_name then
        local suspect_ip = minetest.get_player_ip( suspect_name );
        local resuming_vote = false;
        if not suspect_ip and kick_voting.suspect_by_name[suspect_name] then
            for key, val in pairs(kick_voting.suspect_by_name[suspect_name].ip_list) do    --remember suspect last IP
                suspect_ip = key
            end
            resuming_vote = true;
        end
        if not suspect_ip then
            minetest.chat_send_player(player_name, "Player <"..suspect_name.."> not online. Cannot start voting.");
        else
            if not kick_voting.suspect_by_name[suspect_name] then --start nev voting if needed (after server restarted)
                kick_voting.suspect_by_name[suspect_name]={};
                kick_voting.suspect_by_name[suspect_name].ip_list={};
                kick_voting.suspect_by_name[suspect_name].ip_voters={};
                if not kick_voting.suspect_by_ip[suspect_ip] then
                    kick_voting.suspect_by_ip[suspect_ip] = {};
                    kick_voting.suspect_by_ip[suspect_ip].votes = 0;
                end
                kick_voting.suspect_by_name[suspect_name].ip_list[suspect_ip] = kick_voting.suspect_by_ip[suspect_ip];
                if resuming_vote then
                    minetest.chat_send_all("Resuming voting to kick player <"..suspect_name.."> by IP. Come to "..minetest.pos_to_string(pos));
                else
                    minetest.chat_send_all("Voting to kick player <"..suspect_name.."> by IP. Come to "..minetest.pos_to_string(pos));
                end
            end
            itemstack:take_item();
            local formspec = "size[6,3;]"..
                "label[0,0;Vote to kick player<".. suspect_name .."> from the game?]"..
                "button_exit[0,1;2,0.5;confirm;Yes, kick him.]"..
                "button_exit[3,1;3,0.5;cancel;No, forgive him.]";
            kick_voting.formspec_buffer[player_name] = {suspect=suspect_name, pos=pos};
            minetest.show_formspec(player_name, "kick_voting:vote", formspec)
        end
    elseif suspect_name then
        minetest.chat_send_player(player_name, "Use gold ingot for voting. (Ingot will be consumed)");
    end
end

kick_voting.on_voting = function(player, formname, fields)
    if formname=="kick_voting:vote" and player:is_player() then
        local player_name = player:get_player_name();
        local suspect_name = kick_voting.formspec_buffer[player_name].suspect;
        local player_ip = minetest.get_player_ip( player_name );
        if kick_voting.suspect_by_name[suspect_name].ip_voters[player_ip] then
            local votes_result=0;
            for key, val in pairs(kick_voting.suspect_by_name[suspect_name].ip_list) do    --count votes
                votes_result = val.votes;
            end
            minetest.chat_send_player( player_name, "Already voted! Result:"..votes_result.." of ".. kick_voting.vote_needed );
        elseif suspect_name then
            if fields.confirm then
                kick_voting.suspect_by_name[suspect_name].ip_voters[player_ip] = "voted";
                kick_voting.vote(player_name, suspect_name);
            elseif fields.cancel then
                kick_voting.suspect_by_name[suspect_name].ip_voters[player_ip] = "voted";
                kick_voting.unvote(player_name, suspect_name);
            end
            kick_voting:save();
        end
    end
end

kick_voting.register_vote = function(player_name, suspect_name, pos)
    local suspect_ip = minetest.get_player_ip( suspect_name );
    if suspect_ip then
        minetest.chat_send_all("Voting to kick player <"..suspect_name..">  Come to "..minetest.pos_to_string(pos));
        if kick_voting.suspect_by_name[suspect_name] then
            if not kick_voting.suspect_by_ip[suspect_ip] then
                local votes = 0;--search current vote result
                for key, val in pairs(kick_voting.suspect_by_name[suspect_name].ip_list) do
                    votes = val.votes;
                end
                kick_voting.suspect_by_ip[suspect_ip] = {};
                kick_voting.suspect_by_ip[suspect_ip].votes = votes;
            end
        else
            kick_voting.suspect_by_name[suspect_name]={};
            kick_voting.suspect_by_name[suspect_name].ip_list={};
            kick_voting.suspect_by_name[suspect_name].ip_voters={};
            if not kick_voting.suspect_by_ip[suspect_ip] then
                kick_voting.suspect_by_ip[suspect_ip] = {};
                kick_voting.suspect_by_ip[suspect_ip].votes = 0;
            end
            kick_voting.suspect_by_name[suspect_name].ip_list[suspect_ip] = kick_voting.suspect_by_ip[suspect_ip];
        end
    elseif kick_voting.suspect_by_name[suspect_name] then
        minetest.chat_send_all("Voting to kick player <"..suspect_name.."> by IP. Come to "..minetest.pos_to_string(pos));
    end
end

kick_voting.vote = function(player_name, suspect_name)
    local suspect_ip = minetest.get_player_ip( suspect_name );
    if suspect_ip and not kick_voting.suspect_by_ip[suspect_ip] then   --suspect hawe new ip. adding
        local votes = 0;--search current vote result
        for key, val in pairs(kick_voting.suspect_by_name[suspect_name].ip_list) do
            votes = val.votes;
        end
        kick_voting.suspect_by_ip[suspect_ip] = {};
        kick_voting.suspect_by_ip[suspect_ip].votes = votes;
    end
    if suspect_ip and not kick_voting.suspect_by_name[suspect_name].ip_list[suspect_ip] then   --suspect hawe new ip, or new name. linking
        kick_voting.suspect_by_name[suspect_name].ip_list[suspect_ip] = kick_voting.suspect_by_ip[suspect_ip];
    end
    local votes_result=0;
    for key, val in pairs(kick_voting.suspect_by_name[suspect_name].ip_list) do    --do vote
        votes_result = val.votes + 1;
        kick_voting.suspect_by_name[suspect_name].ip_list[key].votes = votes_result;
    end
    minetest.chat_send_all("Voted by <"..player_name.."> to  kick <"..suspect_name..">. Result:"..votes_result.." of ".. kick_voting.vote_needed);
    minetest.log("action", "Voted by <"..player_name.."> to  kick <"..suspect_name..">. Result:"..votes_result.." of ".. kick_voting.vote_needed);
    if votes_result == kick_voting.vote_needed then
        minetest.chat_send_all("Player <"..suspect_name.."> can be punished now." );
    end
end

kick_voting.unvote = function(player_name, suspect_name)
    local suspect_ip = minetest.get_player_ip( suspect_name )
    if suspect_ip and not kick_voting.suspect_by_ip[suspect_ip] then   --suspect hawe new ip. adding
        local votes = 0;--search current vote result
        for key, val in pairs(kick_voting.suspect_by_name[suspect_name].ip_list) do
            votes = val.votes;
        end
        kick_voting.suspect_by_ip[suspect_ip] = {};
        kick_voting.suspect_by_ip[suspect_ip].votes = votes;
    end
    if suspect_ip and not kick_voting.suspect_by_name[suspect_name].ip_list[suspect_ip] then   --suspect hawe new ip, or new name. linking
        kick_voting.suspect_by_name[suspect_name].ip_list[suspect_ip] = kick_voting.suspect_by_ip[suspect_ip];
    end
    local votes_result=0;
    for key, val in pairs(kick_voting.suspect_by_name[suspect_name].ip_list) do    --do vote
        votes_result = val.votes - 1;
        kick_voting.suspect_by_name[suspect_name].ip_list[key].votes = votes_result;
    end
    minetest.chat_send_all("Voted by <"..player_name.."> to forgive <"..suspect_name..">. Result:"..votes_result.." of ".. kick_voting.vote_needed);
    minetest.log("action", "Voted by <"..player_name.."> to forgive <"..suspect_name..">. Result:"..votes_result.." of ".. kick_voting.vote_needed)
    if votes_result == (kick_voting.vote_needed-1) then
        minetest.chat_send_all("Player <"..suspect_name.."> is forgiven." );
    end
end

minetest.register_on_player_receive_fields( kick_voting.on_voting );

minetest.register_node("kick_voting:table", {
	description = "Voting table",
	tiles = {"kick_voting_top.png", "kick_voting.png"},
	is_ground_content = false,
	groups = {cracky=3,level=3,disable_jump=1},
    is_ground_content = false,
    after_place_node = kick_voting.after_place_node,
    on_receive_fields = kick_voting.receive_config_fields,
    on_rightclick = kick_voting.on_rightclick,
});


minetest.register_craft({
	output = 'kick_voting:table',
	recipe = {
		{'', 'default:bookshelf', ''},
		{'default:gold_ingot', 'default:gold_ingot', 'default:gold_ingot'},
		{'default:gold_ingot', '', 'default:gold_ingot'},
	}
});

--And here is what happens with player, affected by votes
minetest.register_on_respawnplayer(function(suspect)
    local suspect_name = suspect:get_player_name();
    local suspect_ip = minetest.get_player_ip( suspect_name );
    if kick_voting.suspect_by_ip[suspect_ip] and kick_voting.suspect_by_ip[suspect_ip].votes>=kick_voting.vote_needed then
        suspect:setpos( {x=0, y=-2, z=0} );
        minetest.chat_send_all("Player <"..suspect_name.."> sent to jail because of voting");
        return true
    end
end);