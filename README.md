# CreamBun

A cozy isometric RPG about foraging, brewing, and building a life in the wild.

---

## Theme

CreamBun is a cozy life-sim RPG set in a lush, peaceful wilderness. The tone is warm and unhurried — there are no enemies to defeat and no world to save. Progress is measured in full shelves, satisfied customers, and a home that keeps getting a little more cosy. The world rewards curiosity: wandering off the beaten path is always worth it.

---

## Setting

The game takes place in the **Hopster Forest**, a wood full of delicious and useful items that can be discovered by Cream Bun. Nearby, there is a small village with a market at which the player can buy, sell, and trade foraged items with villagers.

### Plants

The forest includes many plants from which items can be harvested. Some examples include:

| Plant         | Description                            | Usable components                     |
| ------------- | -------------------------------------- | ------------------------------------- |
| Horsenut Tree | Large deciduous tree                   | Nut, Leaf, Bark, Wood                 |
| Skydrop       | Small six-petaled flower               | Petals                                |
| Bounce Berry  | Herbacious plant, source of munch root | Berry, Leaf, Root                     |

### Items

| Item          | Description                        | Effect            | Harvesting Method | Price |
| ------------- | ---------------------------------- | ----------------- | ----------------- | ----- |
| Juice Fruit   | Large fruit                        | Satisfaction      | Picking           | 5gp   |
| Munch Root    | Small, tasty root                  | Satisfaction      | Pulling           | 3gp   |
| Horsenut Leaf | Small leaf, bitter, a little salty | Heal sore throat  | Picking           | 10gp  |
| Horsenut      | Medium nut                         | Heal cough        | Picking           | 15gp  |
| Hoppergrass   | Large grass                        | Increase speed    | Cutting           | 20gp  |

---

## Art Style

The game uses a top-down isometric perspective with a soft, cute pixel art aesthetic. Colours are warm and saturated, with chunky sprites and gentle animations. The world should feel handcrafted and inviting — like a children's book illustration brought to life on a grid. Seasonal changes affect the colour palette and what can be foraged, keeping the world feeling alive throughout the year.

---

## Player Character

You play as **Cream Bun** — a small, round creature that looks exactly like a freshly baked cream bun. They have a little tuft of hair poking up from the top of their head and a small puff ball tail. Cream Bun doesn't talk much, but they express a lot through their animations: bouncing with excitement when they find a rare ingredient, drooping sadly in the rain, wiggling their tail when a customer loves a drink.

Cream Bun has no combat skills. Their talents lie entirely in their nose (exceptional at sniffing out ingredients) and their hands (surprisingly dexterous for a bun).

---

## Story

Cream Bun has just moved into a small, overgrown plot at the edge of the Whispering Grove. The previous occupant left behind a wobbly old brewing stand and a hand-drawn map of foraging spots — some of which are marked with little question marks.

There's no grand quest. Cream Bun wants to build something of their own: a proper home, a thriving little shop, and maybe, over time, a reputation as the best brewer in the region. Along the way they'll meet the locals who visit the market, uncover the mystery of who used to live on their plot, and slowly learn what the question marks on the map are hiding.

### Intro

The game starts in a small bookshop owned by an NPC named Doug. Within the bookshop, the player finds a book on foraging. The opening sequence shows the player flipping through the book, then zooms into each page where critical game instructions for the most basic aspects of gameplay are displayed. The player confirms each page once they have had a chance to read through it.

Next, there is dialog with Doug where he asks who you are (the player is prompted to enter their name) and why you are interested in foraging (with multiple choice questions that establish the basis of the player's skill tree). The player is about to leave when Doug mentions that they should talk to Phillip because he is selling a small plot of land that would be an excellent place for the player to settle in order to start foraging.

---

## Game Mechanics

### Foraging
Cream Bun explores the wilderness around their home to gather ingredients — berries, herbs, mushrooms, flowers, bark, and stranger things deeper in the grove. What's available changes with the seasons and weather. Some items only appear at night, or after rain, or in spots you have to find yourself.

Each different source of foraged items has an associated mini-game that the player must play to obtain the foraged item. The better the player performs in the mini game, the higher quality the item that is obtained. Failing the game yields no items at all.

### Brewing
Foraged ingredients are combined at a brewing stand to produce drinks. Recipes are discovered by experimenting with combinations. Each drink has different properties that affect how customers respond — some are refreshing, some are calming, some have effects that are harder to predict. Sometimes recipes appear in the forest, especially when the character has been experimenting for a while without discovering a viable recipe on their own.

Brewing is accomplished by connecting a series of different apparatuses that can be obtained at the market in exchange for items. Some of this equipment breaks down after continued use and the player must play a mini-game to fix the apparatus.

### The Market
Cream Bun sells their brews at a weekly market stall. Customers have preferences and moods. Selling the right drink to the right customer builds reputation, which unlocks new buyers, special orders, and access to ingredients you can't forage yourself or new equipment. Customers might drop hints about their preferences in conversation, or about the needs of other NPCs in the market.

### Home Upgrades
The home base starts small and run-down. Using materials gathered while foraging, Cream Bun can repair and expand their home, adding new facilities such as a drying rack, a fermenting cellar, a greenhouse, and a proper storefront. Each facility unlocks new production options, recipes, and equipment.

### Progression
There are two sources of progress in the game. One source is through industry: upgrading facilities, discovering recipes, building relationships with market regulars, and gradually uncovering more of the map. The other source is through experience: each successful brew increases the character's level and at each level, there is an optional skill that can be unlocked that allows the character to specialize in new ways to convert foraged items into useful tools, recipes, or equipment that can result in the creation of more valuable brews to sell. Experience can create shortcuts in mini-games to make it easier for the player to succeed.

## Controls
The player can move around local maps with their arrow keys, WASD, or game pad d-pad buttons. They can also open a "planner book" interface that acts as the main menu UI for the game. The planner has tabs for the following functions:

* Player equipment and inventory
* Map
* TODO list
* Game settings
* Session management (New, Save, Load, Quit)

The player is able to fast travel between local maps using the map tab in their planner.

---

## Built With

- [Godot 4](https://godotengine.org/) — game engine
- GDScript — scripting language
