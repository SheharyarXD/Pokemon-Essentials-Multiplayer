Events.onTrainerPartyLoad += proc { |_sender, trainer|
  if trainer   # An NPCTrainer object containing party/items/lose text, etc.
    if (trainer[0].trainer_type==:EVILPLAYERMALE || $game_switches[533])  #the clone trainer type
      partytoload=$Trainer.party
      for i in 0...6
        if i<$Trainer.party_count && !partytoload[i].egg?
          trainer[0].party[i]=partytoload[i].clone
          trainer[0].party[i].makeShadow
          trainer[0].party[i].makeShiny
          trainer[0].party[i].level + 5
          trainer[0].party[i].calc_stats
          trainer[0].party[i].heal     #remove this comment to make a perfectly healed
        else                            #copy of the party
          trainer[0].party.pop()
        end
      end
    end
  end
}
