#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=
#
#  Showdown JSON Importer for Pokémon Essentials by AceOfSpadesProduc100
#
#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=
# Get the JSON library from the folder of the below name
$:.push File.join(Dir.pwd, "Ruby Library 3.0.0")
# Import the library
require 'json'
def importteam
	filename = @scene.pbEnterText(_INTL("Name? (Case insensitive)"),1,12)
	begin
		file = File.read("Saved teams/" + filename + ".json")
		data_hash = JSON.parse(file)
		data_hash['teams'][0]['pokemon'].each do |i|
			#.upcase.gsub(/\W/,'').to_sym means to convert into uppercase, include only letters and no spaces, and convert into a Ruby symbol, a variable with a : at the beginning
			p = Pokemon.new(i['name'].upcase.gsub(/\W/,'').to_sym,i['level'] ? i['level'] : 50)
			plevel = i['level'] ? i['level'] : 50
			p.item = i['item'].upcase.gsub(/\W/,'').to_sym if i['item']
			p.poke_ball = i['ball'].upcase.gsub(/\W/,'').to_sym if i['ball']
			if i['moves'] && i['moves'].length > 0
				i['moves'].each do |j|
					p.learn_move(j.upcase.gsub(/\W/,'').to_sym)
				end
			else
				p.reset_moves
			end
			p.form = i['form'] if i['form']
			if i['gender'] == 'M'
				p.makeMale
			else
				p.makeFemale
			end
			p.ability= i['ability'] if i['ability']
			p.ability_index = i['ability_index'] if i['ability_index']
			p.shiny = i['shiny'] if i['shiny']
			p.nature = i['nature'].upcase.gsub(/\W/,'').to_sym if i['nature']
			if i['ivs']
				p.iv[:HP] = i['ivs']['HP'] ? i['ivs']['HP'] : p.iv[:HP] = [plevel / 2, Pokemon::IV_STAT_LIMIT].min
				p.iv[:ATTACK] = i['ivs']['Atk'] ? i['ivs']['Atk'] : p.iv[:ATTACK] = [plevel / 2, Pokemon::IV_STAT_LIMIT].min
				p.iv[:DEFENSE] = i['ivs']['Def'] ? i['ivs']['Def'] : p.iv[:DEFENSE] = [plevel / 2, Pokemon::IV_STAT_LIMIT].min
				p.iv[:SPECIAL_ATTACK] = i['ivs']['SpA'] ? i['ivs']['SpA'] : p.iv[:SPECIAL_ATTACK] = [plevel / 2, Pokemon::IV_STAT_LIMIT].min
				p.iv[:SPECIAL_DEFENSE] = i['ivs']['SpD'] ? i['ivs']['SpD'] : p.iv[:SPECIAL_DEFENSE] = [plevel / 2, Pokemon::IV_STAT_LIMIT].min
				p.iv[:SPEED] = i['ivs']['Spe'] ? i['ivs']['Spe'] : p.iv[:SPEED] = [plevel / 2, Pokemon::IV_STAT_LIMIT].min
			else
				p.iv[:HP] = [plevel / 2, Pokemon::IV_STAT_LIMIT].min
				p.iv[:ATTACK] = [plevel / 2, Pokemon::IV_STAT_LIMIT].min
				p.iv[:DEFENSE] = [plevel / 2, Pokemon::IV_STAT_LIMIT].min
				p.iv[:SPECIAL_ATTACK] = [plevel / 2, Pokemon::IV_STAT_LIMIT].min
				p.iv[:SPECIAL_DEFENSE] = [plevel / 2, Pokemon::IV_STAT_LIMIT].min
				p.iv[:SPEED] = [plevel / 2, Pokemon::IV_STAT_LIMIT].min
			end
			if i['evs']
				p.ev[:HP] = i['evs']['HP'] ? i['evs']['HP'] : p.ev[:HP] = [plevel * 3 / 2, Pokemon::EV_LIMIT / 6].min
				p.ev[:ATTACK] = i['evs']['Atk'] ? i['evs']['Atk'] : p.ev[:ATTACK] = [plevel * 3 / 2, Pokemon::EV_LIMIT / 6].min
				p.ev[:DEFENSE] = i['evs']['Def'] ? i['evs']['Def'] : p.ev[:DEFENSE] = [plevel * 3 / 2, Pokemon::EV_LIMIT / 6].min
				p.ev[:SPECIAL_ATTACK] = i['evs']['SpA'] ? i['evs']['SpA'] : p.ev[:SPECIAL_ATTACK] = [plevel * 3 / 2, Pokemon::EV_LIMIT / 6].min
				p.ev[:SPECIAL_DEFENSE] = i['evs']['SpD'] ? i['evs']['SpD'] : p.ev[:SPECIAL_DEFENSE] = [plevel * 3 / 2, Pokemon::EV_LIMIT / 6].min
				p.ev[:SPEED] = i['evs']['Spe'] ? i['evs']['Spe'] : p.ev[:SPEED] = [plevel * 3 / 2, Pokemon::EV_LIMIT / 6].min
			else
				p.ev[:HP] = [plevel * 3 / 2, Pokemon::EV_LIMIT / 6].min
				p.ev[:ATTACK] = [plevel * 3 / 2, Pokemon::EV_LIMIT / 6].min
				p.ev[:DEFENSE] = [plevel * 3 / 2, Pokemon::EV_LIMIT / 6].min
				p.ev[:SPECIAL_ATTACK] = [plevel * 3 / 2, Pokemon::EV_LIMIT / 6].min
				p.ev[:SPECIAL_DEFENSE] = [plevel * 3 / 2, Pokemon::EV_LIMIT / 6].min
				p.ev[:SPEED] = [plevel * 3 / 2, Pokemon::EV_LIMIT / 6].min
			end
			p.happiness = i['happiness'] if i['happiness']
			p.name = i['nickname'] if i['nickname']
			p.owner.language = i['language'] if i['language']
			p.timeReceived = Time.at(i['timeReceived']) if i['timeReceived']
			p.calc_stats
			(0) rescue nil; pbAddPokemonSilent(p)
		end
		pbMessage(_INTL($Trainer.name + "\\se[] obtained some Pokémon!\\me[Pkmn get]\\wtnp[30]"))
	rescue
		pbMessage(_INTL("An error occurred. Check for JSON-specific errors in a JSON validator, or refer to \"showdowntoessentialsguide.txt\" for team-specific errors.")) 
	end
end