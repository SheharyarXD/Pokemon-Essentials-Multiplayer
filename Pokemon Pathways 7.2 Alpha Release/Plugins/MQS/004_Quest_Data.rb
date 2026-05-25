module QuestModule
  
  # You don't actually need to add any information, but the respective fields in the UI will be blank or "???"
  # I included this here mostly as an example of what not to do, but also to show it's a thing that exists
  Quest0 = {
  
  }
  
  # Here's the simplest example of a single-stage quest with everything specified
  Quest1 = {
    :ID => "1",
    :Name => "Introductions",
    :QuestGiver => "Little Boy",
    :Stage1 => "Look for clues.",
    :Location1 => "Lappet Town",
    :QuestDescription => "Some wild Pokémon stole a little boy's favourite toy. Find those troublemakers and help him get it back.",
    :RewardString => "Something shiny!"
  }
  
  # Here's an extension of the above that includes multiple stages
  Quest2 = {
    :ID => "2",
    :Name => "Introductions",
    :QuestGiver => "Little Boy",
    :Stage1 => "Look for clues.",
    :Stage2 => "Follow the trail.",
    :Stage3 => "Catch the troublemakers!",
    :Location1 => "Lappet Town",
    :Location2 => "Viridian Forest",
    :Location3 => "Route 3",
    :QuestDescription => "Some wild Pokémon stole a little boy's favourite toy. Find those troublemakers and help him get it back.",
    :RewardString => "Something shiny!"
  }
  
  # Here's an example of a quest with lots of stages that also doesn't have a stage location defined for every stage
  Quest3 = {
    :ID => "3",
    :Name => "Last-minute chores",
    :QuestGiver => "Grandma",
    :Stage1 => "A",
    :Stage2 => "B",
    :Stage3 => "C",
    :Stage4 => "D",
    :Stage5 => "E",
    :Stage6 => "F",
    :Stage7 => "G",
    :Stage8 => "H",
    :Stage9 => "I",
    :Stage10 => "J",
    :Stage11 => "K",
    :Stage12 => "L",
    :Location1 => "nil",
    :Location2 => "nil",
    :Location3 => "Dewford Town",
    :QuestDescription => "Isn't the alphabet longer than this?",
    :RewardString => "Chicken soup!"
  }
  
  # Here's an example of not defining the quest giver and reward text
  Quest4 = {
    :ID => "4",
    :Name => "A new beginning",
    :QuestGiver => "nil",
    :Stage1 => "Turning over a new leaf... literally!",
    :Stage2 => "Help your neighbours.",
    :Location1 => "Milky Way",
    :Location2 => "nil",
    :QuestDescription => "You crash landed on an alien planet. There are other humans here and they look hungry...",
    :RewardString => "nil"
  }
  
  # Other random examples you can look at if you want to fill out the UI and check out the page scrolling
  Quest5 = {
    :ID => "5",
    :Name => "All of my friends",
    :QuestGiver => "Barry",
    :Stage1 => "Meet your friends near Acuity Lake.",
    :QuestDescription => "Barry told me that he saw something cool at Acuity Lake and that I should go see. I hope it's not another trick.",
    :RewardString => "You win nothing for giving in to peer pressure."
  }
  
  Quest6 = {
    :ID => "6",
    :Name => "The journey begins",
    :QuestGiver => "Professor Oak",
    :Stage1 => "Deliver the parcel to the Pokémon Mart in Viridian City.",
    :Stage2 => "Return to the Professor.",
    :Location1 => "Viridian City",
    :Location2 => "nil",
    :QuestDescription => "The Professor has entrusted me with an important delivery for the Viridian City Pokémon Mart. This is my first task, best not mess it up!",
    :RewardString => "nil"
  }
  
  Quest7 = {
    :ID => "7",
    :Name => "Close encounters of the... first kind?",
    :QuestGiver => "nil",
    :Stage1 => "Make contact with the strange creatures.",
    :Location1 => "Rock Tunnel",
    :QuestDescription => "A sudden burst of light, and then...! What are you?",
    :RewardString => "A possible probing."
  }
  
  Quest8 = {
    :ID => "8",
    :Name => "These boots were made for walking",
    :QuestGiver => "Musician #1",
    :Stage1 => "Listen to the musician's, uhh, music.",
    :Stage2 => "Find the source of the power outage.",
    :Location1 => "nil",
    :Location2 => "Celadon City Sewers",
    :QuestDescription => "A musician was feeling down because he thinks no one likes his music. I should help him drum up some business."
  }
  
  Quest9 = {
    :ID => "9",
    :Name => "Got any grapes?",
    :QuestGiver => "Duck",
    :Stage1 => "Listen to The Duck Song.",
    :Stage2 => "Try not to sing it all day.",
    :Location1 => "YouTube",
    :QuestDescription => "Let's try to revive old memes by listening to this funny song about a duck wanting grapes.",
    :RewardString => "A loss of braincells. Hurray!"
  }
  
  Quest10 = {
    :ID => "10",
    :Name => "Singing in the rain",
    :QuestGiver => "Some old dude",
    :Stage1 => "I've run out of things to write.",
    :Stage2 => "If you're reading this, I hope you have a great day!",
    :Location1 => "Somewhere prone to rain?",
    :QuestDescription => "Whatever you want it to be.",
    :RewardString => "Wet clothes."
  }
  
  Quest11 = {
    :ID => "11",
    :Name => "When is this list going to end?",
    :QuestGiver => "Me",
    :Stage1 => "When IS this list going to end?",
    :Stage2 => "123",
    :Stage3 => "456",
    :Stage4 => "789",
    :QuestDescription => "I'm losing my sanity.",
    :RewardString => "nil"
  }
  
  Quest12 = {
    :ID => "12",
    :Name => "The laaast melon",
    :QuestGiver => "Some stupid dodo",
    :Stage1 => "Fight for the last of the food.",
    :Stage2 => "Don't die.",
    :Location1 => "A volcano/cliff thing?",
    :Location2 => "Good advice for life.",
    :QuestDescription => "Tea and biscuits, anyone?",
    :RewardString => "Food, glorious food!"
  }

  Quest13 = {
    :ID => "13",
    :Name => "Stop Watching Me!",
    :QuestGiver => "Arcade Girl",
    :Stage1 => "Confront the stalker.",
    :Location1 => "Little Maw Arcade",
    :QuestDescription => "An arcade girl has informed me of a man watching her.  She wants me to Resolve the situation.",
	:RewardString => "Rare Candy"
  }
  
  Quest14 = {
    :ID => "14",
    :Name => "Creep's Hitmonchan!",
    :QuestGiver => "Secret Quest!",
    :Stage1 => "Confront or Ignore Hitmonchan!",
    :Location1 => "Little Maw Arcade",
    :QuestDescription => "While attempting to resolve a conflict with a stalker, I ended up angering him and as a result, he's summoned his Hitmonchan to fight me, but I have no Pokemon! Fight Himonchan???",
	:RewardString => "nil"
  }
  
  Quest15 = {
    :ID => "15",
    :Name => "Card Champion Alex",
    :QuestGiver => "Arcade Staff",
    :Stage1 => "Discover & Win against Alex!",
    :Location1 => "Little Maw Arcade",
    :QuestDescription => "I've been asked by the Arcade Staff to find and defeat Card Champion Alex at her own card game!",
	:RewardString => "Rare Card"
  }
  
  Quest16 = {
    :ID => "16",
    :Name => "Missing Brother",
    :QuestGiver => "Camper Girl",
    :Stage1 => "Find Camper Girl's Lost Brother!",
    :Location1 => "Lush Forest",
    :QuestDescription => "I agreed to help find a camper girl's brother. He is lost somewhere in Lush Forest.",
	:RewardString => "Berry | Charm"
  }
  
  Quest17 = {
    :ID => "17",
    :Name => "Precious Item",
    :QuestGiver => "Rich Boy",
    :Stage1 => "Locate the lost item!",
    :Location1 => "Lush Forest",
    :QuestDescription => "I decided to search for an item a rich man lost. It is somewhere in Lush Forest.",
	:RewardString => "500p"
  }
  
   Quest18	= {
    :ID => "18",
    :Name => "Dropped Monocle",
    :QuestGiver => "Gentleman",
    :Stage1 => "Pick up Monocle below the bridge!",
    :Location1 => "Green Hills",
    :QuestDescription => "An elderly gentleman has tasked me with retrieveing his dropped monocle under the bridge in Green Hills.",
	:RewardString => "Charm | Item"
  }
  
   Quest19 = {
    :ID => "19",
    :Name => "Brokendown Truck",
    :QuestGiver => "Trucker",
    :Stage1 => "Find the truck engineer!",
    :Location1 => "Green Hills",
    :QuestDescription => "A man who's truck has broken down tasked me with finding the truck engineer he called! He said the truck engineer is located somewhere in Green Hills!",
	:RewardString => "Charm | Item"
  }
  
  Quest20	= {
    :ID => "20",
    :Name => "Missing Sisters",
    :QuestGiver => "Youngest Sibling",
    :Stage1 => "Check up on both sisters!",
    :Location1 => "Green Hills",
    :QuestDescription => "A kid lost his sisters while exploring, he wants me to find them in Green Hills!",
	:RewardString => "Charm | Item"
  }
  
  Quest21	= {
    :ID => "21",
    :Name => "Forgotten Clipboard",
    :QuestGiver => "Field Scientist",
    :Stage1 => "Deliver the dropped clipboard!",
    :Location1 => "Mt. Grassland",
    :QuestDescription => "A Scientist seems to have dropped his clipboard while escaping the overwelming wild Pokemon! It contains important data! He wants me to Enter the D-Rank Cave, Find his clipboard and bring it to him!",
	:RewardString => "Key Item | Charm"
  }
  
  Quest22	= {
    :ID => "22",
    :Name => "Slacker Officer",
    :QuestGiver => "Little Maw Sheriff",
    :Stage1 => "Speak to the Police officer!",
    :Location1 => "Little Maw Arcade",
    :QuestDescription => "The sheriff of little maw promised to pay me part of his slacker subbordinate's paycheck if I get him to come in!",
	:RewardString => "2000p"
  }

  Quest23	= {
    :ID => "23",
    :Name => "Base of Operations",
    :QuestGiver => "Former Team Leader",
    :Stage1 => "Find a Base of Operations",
    :Location1 => "C-Rank Floor Field OR West City District",
    :QuestDescription => "Look for a base of operations somewhere in the C-Rank floor fields OR West City District to become a true Boss!",
	:RewardString => "Base of Operations"
  }

Quest24	= {
    :ID => "24",
    :Name => "Flock of Fearow",
    :QuestGiver => "Riverside Road Girl",
    :Stage1 => "Defeat the Flock of Fearow",
    :Location1 => "Riverside Road",
    :QuestDescription => "Find and defeat the flock of Fearow bothering someone!",
	:RewardString => "1000p | Light"
  }

Quest25	= {
    :ID => "25",
    :Name => "Electric Experimentation",
    :QuestGiver => "Electric Scientist",
    :Stage1 => "Deliver Joltik",
    :Location1 => "Thunder Factory",
    :QuestDescription => "Deliver a Joltik to the Cruel scientist.",
	:RewardString => "??? | Dark"
}

Quest26	= {
    :ID => "26",
    :Name => "The Resentful Brother",
    :QuestGiver => "Young Trainer",
    :Stage1 => "Pick up Grave Pokemon",
    :Location1 => "Haunted Manor",
    :QuestDescription => "Find the pokemon of the resentful brother!",
	:RewardString => "??? | Dark"
  
  }

Quest27	= {
    :ID => "27",
    :Name => "Haunted Shrine",
    :QuestGiver => "D-Class Students",
    :Stage1 => "Meet with D-Class at night",
    :Location1 => "Academy Island Front",
    :QuestDescription => "There's been rumors of other students witnessing a haunted shrine. Yariette, Akiza, Hyun and I have agreed to meet at the shrine when it's night to investigate.",
	:RewardString => "???"
  
  }
end
