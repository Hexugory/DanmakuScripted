--Decker
do
    Decker = {}

    -- provide unique ID starting from 20 for present decks
    local nextID
    do
        local _nextID = 20
        nextID = function()
            _nextID = _nextID + 1
            return tostring(_nextID)
        end
    end

    -- Asset signature (equality comparison)
    local function assetSignature(assetData)
        return table.concat({
            assetData.FaceURL,
            assetData.BackURL,
            assetData.NumWidth,
            assetData.NumHeight,
            assetData.BackIsHidden and 'hb' or '',
            assetData.UniqueBack and 'ub' or ''
        })
    end
    -- Asset ID storage to avoid new ones for identical assets
    local idLookup = {}
    local function assetID(assetData)
        local sig = assetSignature(assetData)
        local key = idLookup[sig]
        if not key then
            key = nextID()
            idLookup[sig] = key
        end
        return key
    end

    local assetMeta = {
        deck = function(self, cardNum, options)
            return Decker.AssetDeck(self, cardNum, options)
        end
    }
    assetMeta = {__index = assetMeta}

    -- Create a new CustomDeck asset
    function Decker.Asset(face, back, options)
        local asset = {}
        options = options or {}
        asset.data = {
            FaceURL = face or error('Decker.Asset: faceImg link required'),
            BackURL = back or error('Decker.Asset: backImg link required'),
            NumWidth = options.width or 1,
            NumHeight = options.height or 1,
            BackIsHidden = options.hiddenBack or false,
            UniqueBack = options.uniqueBack or false
        }
        -- Reuse ID if asset existing
        asset.id = assetID(asset.data)
        return setmetatable(asset, assetMeta)
    end
    -- Pull a Decker.Asset from card JSONs CustomDeck entry
    local function assetFromData(assetData)
        return setmetatable({data = assetData, id = assetID(assetData)}, assetMeta)
    end

    -- Create a base for JSON objects
    function Decker.BaseObject()
        return {
            Name = 'Base',
            Transform = {
                posX = 0, posY = 5, posZ = 0,
                rotX = 0, rotY = 0, rotZ = 0,
                scaleX = 1, scaleY = 1, scaleZ = 1
            },
            Nickname = '',
            Description = '',
            ColorDiffuse = { r = 1, g = 1, b = 1 },
            Locked = false,
            Grid = true,
            Snap = true,
            Autoraise = true,
            Sticky = true,
            Tooltip = true,
            GridProjection = false,
            Hands = false,
            XmlUI = '',
            LuaScript = '',
            LuaScriptState = '',
            GUID = 'deadbf'
        }
    end
    -- Typical paramters map with defaults
    local commonMap = {
        name   = {field = 'Nickname',    default = ''},
        desc   = {field = 'Description', default = ''},
        script = {field = 'LuaScript',   default = ''},
        xmlui  = {field = 'XmlUI',       default = ''},
        scriptState = {field = 'LuaScriptState', default = ''},
        locked  = {field = 'Locked',  default = false},
        tooltip = {field = 'Tooltip', default = true},
        guid    = {field = 'GUID',    default = 'deadbf'},
    }
    -- Apply some basic parameters on base JSON object
    function Decker.SetCommonOptions(obj, options)
        options = options or {}
        for k,v in pairs(commonMap) do
            -- can't use and/or logic cause of boolean fields
            if options[k] ~= nil then
                obj[v.field] = options[k]
            else
                obj[v.field] = v.default
            end
        end
        -- passthrough unrecognized keys
        for k,v in pairs(options) do
            if not commonMap[k] then
                obj[k] = v
            end
        end
    end
    -- default spawnObjectJSON params since it doesn't like blank fields
    local function defaultParams(params, json)
        params = params or {}
        params.json = json
        params.position = params.position or {0, 5, 0}
        params.rotation = params.rotation or {0, 0, 0}
        params.scale = params.scale or {1, 1, 1}
        if params.sound == nil then
            params.sound = true
        end
        return params
    end

    -- For copy method
    local deepcopy
    deepcopy = function(t)
        local copy = {}
        for k,v in pairs(t) do
           if type(v) == 'table' then
               copy[k] = deepcopy(v)
           else
               copy[k] = v
           end
        end
        return copy
    end
    -- meta for all Decker derived objects
    local commonMeta = {
        -- return object JSON string, used cached if present
        _cache = function(self)
            if not self.json then
                self.json = JSON.encode(self.data)
            end
            return self.json
        end,
        -- invalidate JSON string cache
        _recache = function(self)
            self.json = nil
            return self
        end,
        spawn = function(self, params)
            params = defaultParams(params, self:_cache())
            return spawnObjectJSON(params)
        end,
        copy = function(self)
            return setmetatable(deepcopy(self), getmetatable(self))
        end,
        setCommon = function(self, options)
            Decker.SetCommonOptions(self.data, options)
            return self
        end,
    }
    -- apply common part on a specific metatable
    local function customMeta(mt)
        for k,v in pairs(commonMeta) do
            mt[k] = v
        end
        mt.__index = mt
        return mt
    end

    -- DeckerCard metatable
    local cardMeta = {
        setAsset = function(self, asset)
            local cardIndex = self.data.CardID:sub(-2, -1)
            self.data.CardID = asset.id .. cardIndex
            self.data.CustomDeck = {[asset.id] = asset.data}
            return self:_recache()
        end,
        getAsset = function(self)
            local deckID = next(self.data.CustomDeck)
            return assetFromData(self.data.CustomDeck[deckID])
        end,
        -- reset deck ID to a consistent value script-wise
        _recheckDeckID = function(self)
            local oldID = next(self.data.CustomDeck)
            local correctID = assetID(self.data.CustomDeck[oldID])
            if oldID ~= correctID then
                local cardIndex = self.data.CardID:sub(-2, -1)
                self.data.CardID = correctID .. cardIndex
                self.data.CustomDeck[correctID] = self.data.CustomDeck[oldID]
                self.data.CustomDeck[oldID] = nil
            end
            return self
        end
    }
    cardMeta = customMeta(cardMeta)
    -- Create a DeckerCard from an asset
    function Decker.Card(asset, row, col, options)
        row, col = row or 1, col or 1
        options = options or {}
        local card = Decker.BaseObject()
        card.Name = 'Card'
        card.Hands = true
        -- optional custom fields
        Decker.SetCommonOptions(card, options)
        if options.sideways ~= nil then
            card.SidewaysCard = options.sideways
            -- FIXME passthrough set that field, find some more elegant solution
            card.sideways = nil
        end
        -- CardID string is parent deck ID concat with its 0-based index (always two digits)
        local num = (row-1)*asset.data.NumWidth + col - 1
        num = string.format('%02d', num)
        card.CardID = asset.id .. num
        -- just the parent asset reference needed
        card.CustomDeck = {[asset.id] = asset.data}

        local obj = setmetatable({data = card}, cardMeta)
        obj:_cache()
        return obj
    end


    -- DeckerDeck meta
    local deckMeta = {
        count = function(self)
            return #self.data.DeckIDs
        end,
        -- Transform index into positive
        index = function(self, ind)
            if ind < 0 then
                return self:count() + ind + 1
            else
                return ind
            end
        end,
        swap = function(self, i1, i2)
            local ri1, ri2 = self:index(i1), self:index(i2)
            assert(ri1 > 0 and ri1 <= self:count(), 'DeckObj.rearrange: index ' .. i1 .. ' out of bounds')
            assert(ri2 > 0 and ri2 <= self:count(), 'DeckObj.rearrange: index ' .. i2 .. ' out of bounds')
            self.data.DeckIDs[ri1], self.data.DeckIDs[ri2] = self.data.DeckIDs[ri2], self.data.DeckIDs[ri1]
            local co = self.data.ContainedObjects
            co[ri1], co[ri2] = co[ri2], co[ri1]
            return self:_recache()
        end,
        -- rebuild self.data.CustomDeck based on contained cards
        _rescanDeckIDs = function(self, id)
            local cardIDs = {}
            for k,card in ipairs(self.data.ContainedObjects) do
                local cardID = next(card.CustomDeck)
                if not cardIDs[cardID] then
                    cardIDs[cardID] = card.CustomDeck[cardID]
                end
            end
            -- eeh, GC gotta earn its keep as well
            -- FIXME if someone does shitton of removals, may cause performance issues?
            self.data.CustomDeck = cardIDs
        end,
        remove = function(self, ind, skipRescan)
            local rind = self:index(ind)
            assert(rind > 0 and rind <= self:count(), 'DeckObj.remove: index ' .. ind .. ' out of bounds')
            local card = self.data.ContainedObjects[rind]
            table.remove(self.data.DeckIDs, rind)
            table.remove(self.data.ContainedObjects, rind)
            if not skipRescan then
                self:_rescanDeckIDs(next(card.CustomDeck))
            end
            return self:_recache()
        end,
        removeMany = function(self, ...)
            local indices = {...}
            table.sort(indices, function(e1,e2) return self:index(e1) > self:index(e2) end)
            for _,ind in ipairs(indices) do
                self:remove(ind, true)
            end
            self:_rescanDeckIDs()
            return self:_recache()
        end,
        insert = function(self, card, ind)
            ind = ind or (self:count() + 1)
            local rind = self:index(ind)
            assert(rind > 0 and rind <= (self:count()+1), 'DeckObj.insert: index ' .. ind .. ' out of bounds')
            table.insert(self.data.DeckIDs, rind, card.data.CardID)
            table.insert(self.data.ContainedObjects, rind, card.data)
            local id = next(card.data.CustomDeck)
            if not self.data.CustomDeck[id] then
                self.data.CustomDeck[id] = card.data.CustomDeck[id]
            end
            return self:_recache()
        end,
        reverse = function(self)
            local s,e = 1, self:count()
            while s < e do
                self:swap(s, e)
                s = s+1
                e = e-1
            end
            return self:_recache()
        end,
        cardAt = function(self, ind)
            local rind = self:index(ind)
            assert(rind > 0 and rind <= (self:count()+1), 'DeckObj.insert: index ' .. ind .. ' out of bounds')
            local card = setmetatable({data = deepcopy(self.data.ContainedObjects[rind])}, cardMeta)
            card:_cache()
            return card
        end,
        switchAssets = function(self, replaceTable)
            -- destructure replace table into
            -- [ID_to_replace] -> [ID_to_replace_with]
            -- [new_asset_ID] -> [new_asset_data]
            local idReplace = {}
            local assets = {}
            for oldAsset, newAsset in pairs(replaceTable) do
                assets[newAsset.id] = newAsset.data
                idReplace[oldAsset.id] = newAsset.id
            end
            -- update deckIDs
            for k,cardID in ipairs(self.data.DeckIDs) do
                local deckID, cardInd = cardID:sub(1, -3), cardID:sub(-2, -1)
                if idReplace[deckID] then
                    self.data.DeckIDs[k] = idReplace[deckID] .. cardInd
                end
            end
            -- update CustomDeck data - nil replaced
            for replacedID in pairs(idReplace) do
                if self.data.CustomDeck[replacedID] then
                    self.data.CustomDeck[replacedID] = nil
                end
            end
            -- update CustomDeck data - add replacing
            for _,replacingID in pairs(idReplace) do
                self.data.CustomDeck[replacingID] = assets[replacingID]
            end
            -- update card data
            for k,cardData in ipairs(self.data.ContainedObjects) do
                local deckID = next(cardData.CustomDeck)
                if idReplace[deckID] then
                    cardData.CustomDeck[deckID] = nil
                    cardData.CustomDeck[idReplace[deckID]] = assets[idReplace[deckID]]
                end
            end
            return self:_recache()
        end,
        getAssets = function(self)
            local assets = {}
            for id,assetData in pairs(self.data.CustomDeck) do
                assets[#assets+1] = assetFromData(assetData)
            end
            return assets
        end
    }
    deckMeta = customMeta(deckMeta)
    -- Create DeckerDeck object from DeckerCards
    function Decker.Deck(cards, options)
        options = options or {}
        assert(#cards > 1, 'Trying to create a Decker.deck with less than 2 cards')
        local deck = Decker.BaseObject()
        deck.Name = 'Deck'
        Decker.SetCommonOptions(deck, options)
        deck.DeckIDs = {}
        deck.CustomDeck = {}
        deck.ContainedObjects = {}
        deck.SidewaysCard = options.sideways or false
        for _,card in ipairs(cards) do
            deck.DeckIDs[#deck.DeckIDs+1] = card.data.CardID
            local id = next(card.data.CustomDeck)
            if not deck.CustomDeck[id] then
                deck.CustomDeck[id] = card.data.CustomDeck[id]
            end
            deck.ContainedObjects[#deck.ContainedObjects+1] = card.data
        end

        local obj = setmetatable({data = deck}, deckMeta)
        obj:_cache()
        return obj
    end
    -- Create DeckerDeck from an asset using X cards on its sheet
    function Decker.AssetDeck(asset, cardNum, options)
        cardNum = cardNum or asset.data.NumWidth * asset.data.NumHeight
        local row, col, width = 1, 1, asset.data.NumWidth
        local cards = {}
        for k=1,cardNum do
            cards[#cards+1] = Decker.Card(asset, row, col, {sideways=options.sideways})
            col = col+1
            if col > width then
                row, col = row+1, 1
            end
        end
        return Decker.Deck(cards, options)
    end
end
--End Decker

function tablelength(T)
    local count = 0
    for _ in pairs(T) do count = count + 1 end
    return count
end

expansions = {LunaticExtra = false, ShitTier = false, GarbageTier = false, TerminalExpansion = false, FoxBox = false, YuriParadise = false, EToFS = false, ZhelotRoles = false, WillofFate = false, DBSCharacters = false, GoldenAdditions = false, MUSCLE = false, Traits = false, AdvancedShitposting = false, Wild = false, BullshitTier = false, VastGensokyo = false, PC98 = false, Travel = false, Distrust = false, DumbassCards = false}
DeckerCards = {
    MainCards = {},
    LunaticCards = {},
    IncidentCards = {},
    CharacterCards = {},
    HeroineCards = {},
    PartnerCards = {},
    StageCards = {},
    ExCards = {},
    RevealCards = {},
    TerminalCards = {},
    PrecognitionCards = {},
    NightCards = {},
    TraitCards = {},
    WildCards = {},
    ContractCards = {},
    TravelCards = {},
    ExternalCards = {}
}
PlateSpace = {
    TravelCards = 0,
    NightCards = 0,
    IncidentCards = 0,
    PrecognitionCards = 0,
    ContractCards = 0,
    WildCards = 0,
    LunaticCards = 0,
    MainCards = 0,
    TerminalCards = 0,
    TraitCards = 0
}
remeber = 0

CharacterLocation = {-8.00, 2, 12.00}
cardNamesTable = {}

function onLoad()
    WebRequest.get("https://pastebin.com/raw/pdxWnTgD", function(obj) unCrashCardNames(JSON.decode(obj.text)) end) -- GETs the list of names
    local scriptObjects = getObjectFromGUID("906d21").getObjects()
    for key,value in pairs(scriptObjects) do _G[value.getName()] = value.getGUID() end
end

function unCrashCardNames(list) -- inserts empty entries so we don't try to read nulls and crash
    cardNamesTable = list
    for key,_ in pairs(expansions) do
        if cardNamesTable[key] then
        else
            cardNamesTable[key] = {}
        end
        for key2,_ in pairs(DeckerCards) do
            if cardNamesTable[key][key2] then
            else
                    cardNamesTable[key][key2] = {}
            end
        end
    end
end

function mysplit(inputstr, sep)
    if sep == nil then
            sep = "%s"
    end
    local t={} ; i=1
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
            t[i] = str
            i = i + 1
    end
    return t
end

function toggleExpansion(player, isOn, id)
    local bool = false
    if isOn == "True" then
        bool = true
    end
    expansions[id] = bool
end

function webRequestCallback(webReturn, expansion)
    cardResources = JSON.decode(webReturn.text)
    for deckName,deck in pairs(cardResources) do
        if deck.face then
            if deckName=="HeroineCards" or deckName=="PartnerCards" or deckName=="ExCards" or deckName=="StageCards" then deck.back = "https://i.imgur.com/NQSqNLQ.jpg" end
            local cardAsset = Decker.Asset(deck.face, deck.back, {width = deck.width, height = deck.height, hiddenBack = true})
            for i=1,deck.cards do
                local yc = 1
                local xc = i
                while xc>deck.width do
                    xc = xc-deck.width
                    yc = yc+1
                end
                table.insert(DeckerCards[deckName], Decker.Card(cardAsset, yc, xc, {sideways=(deckName=="CharacterCards"), name = cardNamesTable[expansion][deckName][i] or ''}))
            end
        end
    end
    expansions[expansion] = 'loaded'
end

function waitCondition()
    if remeber == 0 then
        return true
    elseif expansions[remeber] == 'loaded' then
        print('Last expansion done.')
        return true
    else
        return false
    end
end

CDecks = 1

function getMod(deck)
    local done = false
    local mod = 0
    for key,value in pairs(PlateSpace) do
        if done == false and key ~= deck then
            mod = mod + value
        else done = true end
    end
    return mod
end

function BasePlates()
    if basePlatesPlaced then return false end
    local mod = getMod('IncidentCards')
    for i=1,3 do
        getObjectFromGUID(IPlate).takeObject({position = {basePos[1]+1+4*(i)+mod,basePos[2],basePos[3]}, rotation = {0,180,0}, smooth = false}).setLock(true)
    end
    for i=1,3 do
        getObjectFromGUID(IPlate).takeObject({position = {basePos[1]+1+4*(i)+mod,basePos[2]+0.1,basePos[3]-6}, rotation = {0,180,180}, smooth = false}).setLock(true)
    end
    getObjectFromGUID(IDeck).takeObject({position = {basePos[1]+6+mod,basePos[2],basePos[3]+5}, rotation = {0,90,0}, smooth = false}).setLock(true)
    getObjectFromGUID(IDiscard).takeObject({position = {basePos[1]+12+mod,basePos[2],basePos[3]+5}, rotation = {0,90,0}, smooth = false}).setLock(true)
    getObjectFromGUID(ICardsBase).takeObject({position = {basePos[1]+6+mod,2,basePos[3]+5}, rotation = {0,90,180}, smooth = false})

    local mod = getMod('MainCards')
    getObjectFromGUID(MDeck).takeObject({position = {basePos[1]+mod,basePos[2],basePos[3]+4}, rotation = {0,180,0}, smooth = false}).setLock(true)
    getObjectFromGUID(MDiscard).takeObject({position = {basePos[1]+mod,basePos[2],basePos[3]-2}, rotation = {0,180,0}, smooth = false}).setLock(true)
    getObjectFromGUID(BaseRef).takeObject({position = {basePos[1]-2+mod,basePos[2]-0.01,basePos[3]-7}, smooth = false}).setLock(true)
    getObjectFromGUID(Die).takeObject({position = {basePos[1]+mod,basePos[2]-0.01,basePos[3]-7}, smooth = false}).setLock(true)
    getObjectFromGUID(LifeToken).takeObject({position = {basePos[1]-2+mod,basePos[2]-0.01,basePos[3]-9}, smooth = false}).setLock(true)
    getObjectFromGUID(MCardsBase).takeObject({position = {basePos[1]+mod,2,basePos[3]+4}, rotation = {0,180,180}, smooth = false})
    
    getObjectFromGUID(CCardsBase).takeObject({position = CharacterLocation, rotation = {0,90,180}, smooth = false})

    if expansions.ZhelotRoles==false then
        getObjectFromGUID(RHeroineBase).takeObject({position = {-9,2,-22}, rotation = {0,180,0}, smooth = false})
        getObjectFromGUID(RPartnerBase).takeObject({position = {-3,2,-22}, rotation = {0,180,0}, smooth = false})
        getObjectFromGUID(RStageBase).takeObject({position = {3,2,-22}, rotation = {0,180,0}, smooth = false})
        getObjectFromGUID(RExBase).takeObject({position = {9,2,-22}, rotation = {0,180,0}, smooth = false})
        getObjectFromGUID(RRevealBase).takeObject({position = {-5,2,18}, rotation = {0,180,0}, smooth = false})
    end
    basePlatesPlaced = true
    return true
end

function LEPlates()
    if LEPlatesPlaced then return false end
    local mod = getMod('LunaticCards')
    getObjectFromGUID(LDeck).takeObject({position = {basePos[1]+mod,basePos[2],basePos[3]+4}, rotation = {0,180,0}, smooth = false}).setLock(true)
    getObjectFromGUID(LDiscard).takeObject({position = {basePos[1]+mod,basePos[2],basePos[3]-2}, rotation = {0,180,0}, smooth = false}).setLock(true)
    local mod = getMod('MainCards')
    getObjectFromGUID(SeasonDie).takeObject({position = {basePos[1]+2+mod,basePos[2]-0.01,basePos[3]-7}, smooth = false}).setLock(true)
    getObjectFromGUID(ExtraPlate).takeObject({position = {basePos[1]+4+mod,basePos[2]-0.01,basePos[3]-7}, smooth = false}).setLock(true)
    getObjectFromGUID(ExtraCard).takeObject({position = {basePos[1]+6+mod,basePos[2]-0.01,basePos[3]-7}, smooth = false}).setLock(true)
    LEPlatesPlaced = true
    return true
end

function TEPlates()
    if TEPlatesPlaced then return false end
    local mod = getMod('TerminalCards')
    for i=0,2 do
        getObjectFromGUID(TPlate).takeObject({position = {basePos[1]-5+mod-4*(i),basePos[2],basePos[3]}, rotation = {0,180,0}, smooth = false}).setLock(true)
    end
    for i=1,2 do
        getObjectFromGUID(TPlate).takeObject({position = {basePos[1]-5+mod-4*(i),basePos[2],basePos[3]-6}, rotation = {0,180,0}, smooth = false}).setLock(true)
    end
    getObjectFromGUID(TDeck).takeObject({position = {basePos[1]-6+mod,basePos[2],basePos[3]+5}, rotation = {0,90,0}, smooth = false}).setLock(true)
    getObjectFromGUID(TDiscard).takeObject({position = {basePos[1]-12+mod,basePos[2],basePos[3]+5}, rotation = {0,90,0}, smooth = false}).setLock(true)
    getObjectFromGUID(TERef).takeObject({position = {basePos[1]+mod,basePos[2]-0.01,basePos[3]-9}, smooth = false}).setLock(true)
    TEPlatesPlaced = true
    return true
end

function TraitsPlates()
    if TraitsPlatesPlaced then return false end
    local mod = getMod('TraitCards')
    getObjectFromGUID(TraitsDeck).takeObject({position = {basePos[1]-5+mod,basePos[2],basePos[3]+4}, rotation = {0,180,0}, smooth = false}).setLock(true)
    TraitsPlatesPlaced = true
    return true
end

function WildPlates()
    if WildPlatesPlaced then return false end
    local mod = getMod('WildCards')
    getObjectFromGUID(WildDeck).takeObject({position = {basePos[1]+mod,basePos[2],basePos[3]+4}, rotation = {0,180,0}, smooth = false}).setLock(true)
    getObjectFromGUID(WildDeck).takeObject({position = {basePos[1]+mod,basePos[2]+0.1,basePos[3]-2}, rotation = {0,180,180}, smooth = false}).setLock(true)
    WildPlatesPlaced = true
    return true
end
function PC98Plates()
    if PC98PlatesPlaced then return false end
    local mod = getMod('ContractCards')
    getObjectFromGUID(ContractDeck).takeObject({position = {basePos[1]+mod,basePos[2],basePos[3]+4}, rotation = {0,180,0}, smooth = false}).setLock(true)
    getObjectFromGUID(ContractDeck).takeObject({position = {basePos[1]+mod,basePos[2]+0.1,basePos[3]-2}, rotation = {0,180,180}, smooth = false}).setLock(true)
    getObjectFromGUID(PC98Ref).takeObject({position = {basePos[1]-2+mod,basePos[2]-0.01,basePos[3]-7}, smooth = false}).setLock(true)
    PC98PlatesPlaced = true
    return true
end
function doEverything()
    snapPoints = Global.getSnapPoints()
    if #DeckerCards.PrecognitionCards>0 then
        basePos[1] = basePos[1]+2
        PlateSpace.PrecognitionCards = PlateSpace.PrecognitionCards-4
    end
    if #DeckerCards.NightCards>0 then
        --basePos[1] = basePos[1]+2
        --PlateSpace.NightCards = PlateSpace.NightCards-4
    end
    if #DeckerCards.TerminalCards>0 then
        basePos[1] = basePos[1]+7
        PlateSpace.TerminalCards = PlateSpace.TerminalCards-13
    end
    if #DeckerCards.LunaticCards>0 or expansions.LunaticExtra then
        basePos[1] = basePos[1]+2
        PlateSpace.LunaticCards = PlateSpace.LunaticCards-4
    end
    if #DeckerCards.WildCards>0 then
        basePos[1] = basePos[1]+2
        PlateSpace.WildCards = PlateSpace.WildCards-4
    end
    if #DeckerCards.TraitCards>0 then
        basePos[1] = basePos[1]+2
        PlateSpace.TraitCards = PlateSpace.TraitCards-4
    end
    if #DeckerCards.ContractCards>0 then
        basePos[1] = basePos[1]+2
        PlateSpace.ContractCards = PlateSpace.ContractCards-4
    end
    if #DeckerCards.TravelCards>0 then
        basePos[1] = basePos[1]+2
        PlateSpace.TravelCards = PlateSpace.ContractCards-4
    end
    if #DeckerCards.TerminalCards>0 then
        TEPlates()
    end
    if #DeckerCards.LunaticCards>0 or expansions.LunaticExtra then
        LEPlates()
    end
    if #DeckerCards.TraitCards>0 then
        TraitsPlates()
    end
    if #DeckerCards.WildCards>0 then
        WildPlates()
    end
    if #DeckerCards.ContractCards>0 then
        PC98Plates()
    end
    if expansions.WillofFate then
        local mod = getMod('PrecognitionCards')
        getObjectFromGUID(WinterToken).takeObject({position = {basePos[1]-2+mod,basePos[2]-0.01,basePos[3]-7}, smooth = false}).setLock(true)
        getObjectFromGUID(SummerToken).takeObject({position = {basePos[1]+mod,basePos[2]-0.01,basePos[3]-7}, smooth = false}).setLock(true)
        getObjectFromGUID(AutumnToken).takeObject({position = {basePos[1]-2+mod,basePos[2]-0.01,basePos[3]-9}, smooth = false}).setLock(true)
        getObjectFromGUID(SpringToken).takeObject({position = {basePos[1]+mod,basePos[2]-0.01,basePos[3]-9}, smooth = false}).setLock(true)
        local mod = getMod('MainCards')
        getObjectFromGUID(WoFRef).takeObject({position = {basePos[1]+2+mod,basePos[2]-0.01,basePos[3]-9}, smooth = false}).setLock(true)
    end
    if expansions.ShitTier then
        local mod = getMod('MainCards')
        getObjectFromGUID(ChenToken).takeObject({position = {basePos[1]+4+mod,basePos[2]-0.01,basePos[3]-9}, smooth = false}).setLock(true)
        getObjectFromGUID(OkinaToken).takeObject({position = {basePos[1]+6+mod,basePos[2]-0.01,basePos[3]-9}, smooth = false}).setLock(true)
    end
    if expansions.EToFS then
        local mod = getMod('NightCards')
        getObjectFromGUID(SilenceToken).takeObject({position = {basePos[1]+17+mod,basePos[2]-0.01,basePos[3]-7}, smooth = false}).setLock(true)
        getObjectFromGUID(NightButton).takeObject({position = {basePos[1]+19+mod,basePos[2]-0.01,basePos[3]-7}, smooth = false}).setLock(true)
        getObjectFromGUID(LoreButton).takeObject({position = {basePos[1]+17+mod,basePos[2]-0.01,basePos[3]-9}, smooth = false}).setLock(true)
        getObjectFromGUID(ClankButton).takeObject({position = {basePos[1]+19+mod,basePos[2]-0.01,basePos[3]-9}, smooth = false}).setLock(true)
        getObjectFromGUID(Past).takeObject({position = {basePos[1]+17+mod,basePos[2]-0.01,basePos[3]-11}, smooth = false}).setLock(true)
        getObjectFromGUID(GoodFuture).takeObject({position = {basePos[1]+19+mod,basePos[2]-0.01,basePos[3]-11}, smooth = false}).setLock(true)
        getObjectFromGUID(EToFSRef).takeObject({position = {basePos[1]+17+mod,basePos[2]-0.01,basePos[3]-13}, smooth = false}).setLock(true)
    end
    if expansions.Travel then
        local mod = getMod('TravelCards')
        getObjectFromGUID(TravelRef).takeObject({position = {basePos[1]+17+mod,basePos[2]-0.01,basePos[3]-7}, smooth = false}).setLock(true)
    end
    BasePlates()
    if expansions.LunaticExtra then
        local mod = getMod('MainCards')
        getObjectFromGUID(MCardsLunatic).takeObject({position = {basePos[1]+mod,2,basePos[3]+4}, rotation = {0,180,180}, smooth = false})
        local mod = getMod('IncidentCards')
        getObjectFromGUID(ICardsLunatic).takeObject({position = {basePos[1]+6+mod,2,basePos[3]+5}, rotation = {0,90,180}, smooth = false})
        local mod = getMod('LunaticCards')
        getObjectFromGUID(LCardsLunatic).takeObject({position = {basePos[1]+mod,2,basePos[3]+4}, rotation = {0,180,180}, smooth = false})
        getObjectFromGUID(CCardsLunatic).takeObject({position = CharacterLocation, rotation = {0,90,180}, smooth = false})
        CDecks = CDecks+1
        if expansions.ZhelotRoles==false then
            getObjectFromGUID(RExLunatic).takeObject({position = {9,2,-22}, rotation = {0,180,0}, smooth = false})
            getObjectFromGUID(RRevealLunatic).takeObject({position = {-5,2,18}, rotation = {0,180,0}, smooth = false})
        end
    end
    for key,value in pairs(DeckerCards) do
        if #value>1 then
            local tempDeck = Decker.Deck(value, {sideways=key=="CharacterCards"})
            if key=="MainCards" then
                local mod = getMod('MainCards')
                tempDeck:spawn({position = {basePos[1]+mod,2,basePos[3]+4}, rotation = {0,180,180}}).setScale({1.82,1,1.82})
            elseif key=="LunaticCards" then
                local mod = getMod('LunaticCards')
                tempDeck:spawn({position = {basePos[1]+mod,2,basePos[3]+4}, rotation = {0,180,180}}).setScale({1.82,1,1.82})
            elseif key=="IncidentCards" then
                local mod = getMod('IncidentCards')
                tempDeck:spawn({position = {basePos[1]+6+mod,2,basePos[3]+5}, rotation = {0,90,180}}).setScale({1.82,1,1.82})
            elseif key=="HeroineCards" then
                tempDeck:spawn({position = {-9,2,-22}, rotation = {0,180,0}}).setScale({1.82,1,1.82})
            elseif key=="PartnerCards" then
                tempDeck:spawn({position = {-3,2,-22}, rotation = {0,180,0}}).setScale({1.82,1,1.82})
            elseif key=="StageCards" then
                tempDeck:spawn({position = {3,2,-22}, rotation = {0,180,0}}).setScale({1.82,1,1.82})
            elseif key=="ExCards" then
                tempDeck:spawn({position = {9,2,-22}, rotation = {0,180,0}}).setScale({1.82,1,1.82})
            elseif key=="RevealCards" then
                tempDeck:spawn({position = {-5,2,18}, rotation = {0,180,0}}).setScale({1.82,1,1.82})
            elseif key=="TerminalCards" then
                local mod = getMod('TerminalCards')
                tempDeck:spawn({position = {basePos[1]-6+mod,2,basePos[3]+5}, rotation = {0,90,180}}).setScale({1.82,1,1.82})
            elseif key=="PrecognitionCards" then
                local mod = getMod('PrecognitionCards')
                tempDeck:spawn({position = {basePos[1]+mod,2,basePos[3]+4}, rotation = {0,180,180}}).setScale({1.82,1,1.82})
                table.insert(snapPoints, {position = {basePos[1]-5+mod,basePos[2],basePos[3]+4}, rotation = {0,180,180}, rotation_snap = true})
                table.insert(snapPoints, {position = {basePos[1]-5+mod,basePos[2],basePos[3]-2}, rotation = {0,180,180}, rotation_snap = true})
            elseif key=="NightCards" then
                local mod = getMod('NightCards')
                tempDeck:spawn({position = {basePos[1]-6+mod,2,basePos[3]-13}, rotation = {0,90,180}}).setScale({1.82,1,1.82})
                table.insert(snapPoints, {position = {basePos[1]-6+mod,basePos[2],basePos[3]-13}, rotation = {0,90,180}, rotation_snap = true})
                table.insert(snapPoints, {position = {basePos[1]+mod,basePos[2],basePos[3]-13}, rotation = {0,90,180}, rotation_snap = true})
            elseif key=="TraitCards" then
                local mod = getMod('TraitCards')
                tempDeck:spawn({position = {basePos[1]-5+mod,2,basePos[3]+4}, rotation = {0,180,180}}).setScale({1.82,1,1.82})
            elseif key=="WildCards" then
                local mod = getMod('WildCards')
                tempDeck:spawn({position = {basePos[1]+mod,2,basePos[3]+4}, rotation = {0,180,180}}).setScale({1.82,1,1.82})
            elseif key=="ContractCards" then
                local mod = getMod('ContractCards')
                tempDeck:spawn({position = {basePos[1]+mod,2,basePos[3]+4}, rotation = {0,180,180}}).setScale({1.82,1,1.82})
            elseif key=="TravelCards" then
                local mod = getMod('TravelCards')
                tempDeck:spawn({position = {basePos[1]+13+mod,2,basePos[3]+4}, rotation = {0,180,180}}).setScale({1.82,1,1.82})
                table.insert(snapPoints, {position = {basePos[1]+13+mod,basePos[2],basePos[3]+4}, rotation = {0,180,180}, rotation_snap = true})
                table.insert(snapPoints, {position = {basePos[1]+13+mod,basePos[2],basePos[3]-2}, rotation = {0,180,180}, rotation_snap = true})
            elseif key=="ExternalCards" then
                tempDeck:spawn({position = {5,2,18}, rotation = {0,180,0}}).setScale({1.82,1,1.82})
            elseif key=="CharacterCards" then
                tempDeck:spawn({position = CharacterLocation, rotation = {0,90,180}}).setScale({2.55,1,2.55})
            end
        elseif #value==1 then
            if key=="MainCards" then
                local mod = getMod('MainCards')
                value[1]:spawn({position = {basePos[1]+mod,2,basePos[3]+4}, rotation = {0,180,180}}).setScale({1.82,1,1.82})
            elseif key=="LunaticCards" then
                local mod = getMod('LunaticCards')
                value[1]:spawn({position = {basePos[1]+mod,2,basePos[3]+4}, rotation = {0,180,180}}).setScale({1.82,1,1.82})
            elseif key=="IncidentCards" then
                local mod = getMod('IncidentCards')
                value[1]:spawn({position = {basePos[1]+6+mod,2,basePos[3]+5}, rotation = {0,90,180}}).setScale({1.82,1,1.82})
            elseif key=="HeroineCards" then
                value[1]:spawn({position = {-9,2,-22}, rotation = {0,180,0}}).setScale({1.82,1,1.82})
            elseif key=="PartnerCards" then
                value[1]:spawn({position = {-3,2,-22}, rotation = {0,180,0}}).setScale({1.82,1,1.82})
            elseif key=="StageCards" then
                value[1]:spawn({position = {3,2,-22}, rotation = {0,180,0}}).setScale({1.82,1,1.82})
            elseif key=="ExCards" then
                value[1]:spawn({position = {9,2,-22}, rotation = {0,180,0}}).setScale({1.82,1,1.82})
            elseif key=="RevealCards" then
                value[1]:spawn({position = {-5,2,18}, rotation = {0,180,0}}).setScale({1.82,1,1.82})
            elseif key=="TerminalCards" then
                local mod = getMod('TerminalCards')
                value[1]:spawn({position = {basePos[1]-6+mod,2,basePos[3]+5}, rotation = {0,90,180}}).setScale({1.82,1,1.82})
            elseif key=="PrecognitionCards" then
                local mod = getMod('PrecognitionCards')
                value[1]:spawn({position = {basePos[1]+mod,2,basePos[3]+4}, rotation = {0,180,180}}).setScale({1.82,1,1.82})
                table.insert(snapPoints, {position = {basePos[1]+mod,basePos[2],basePos[3]+4}, rotation = {0,180,180}, rotation_snap = true})
                table.insert(snapPoints, {position = {basePos[1]+mod,basePos[2],basePos[3]-2}, rotation = {0,180,180}, rotation_snap = true})
            elseif key=="NightCards" then
                local mod = getMod('NightCards')
                value[1]:spawn({position = {basePos[1]-6+mod,2,basePos[3]-13}, rotation = {0,90,180}}).setScale({1.82,1,1.82})
                table.insert(snapPoints, {position = {basePos[1]+mod,basePos[2],basePos[3]-13}, rotation = {0,90,180}, rotation_snap = true})
                table.insert(snapPoints, {position = {basePos[1]-6+mod,basePos[2],basePos[3]-13}, rotation = {0,90,180}, rotation_snap = true})
            elseif key=="TraitCards" then
                local mod = getMod('TraitCards')
                value[1]:spawn({position = {basePos[1]-5+mod,2,basePos[3]+4}, rotation = {0,180,180}}).setScale({1.82,1,1.82})
            elseif key=="WildCards" then
                local mod = getMod('WildCards')
                value[1]:spawn({position = {basePos[1]+mod,2,basePos[3]+4}, rotation = {0,180,180}}).setScale({1.82,1,1.82})
            elseif key=="ContractCards" then
                local mod = getMod('ContractCards')
                value[1]:spawn({position = {basePos[1]+mod,2,basePos[3]+4}, rotation = {0,180,180}}).setScale({1.82,1,1.82})
            elseif key=="TravelCards" then
                local mod = getMod('TravelCards')
                value[1]:spawn({position = {basePos[1]+13+mod,2,basePos[3]+4}, rotation = {0,180,180}}).setScale({1.82,1,1.82})
                table.insert(snapPoints, {position = {basePos[1]+13+mod,basePos[2],basePos[3]+4}, rotation = {0,180,180}, rotation_snap = true})
                table.insert(snapPoints, {position = {basePos[1]+13+mod,basePos[2],basePos[3]-2}, rotation = {0,180,180}, rotation_snap = true})
            elseif key=="ExternalCards" then
                value[1]:spawn({position = {5,2,18}, rotation = {0,180,0}}).setScale({1.82,1,1.82})
            elseif key=="CharacterCards" then
                value[1]:spawn({value[1]:spawn({position = CharacterLocation, rotation = {0,90,180}}).setScale({2.55,1,2.55})})
            end
        end
    end
    Global.setSnapPoints(snapPoints)
end

function loadExpansions(player, _, id)
    print('Loading expansions...')
    closePanel(nil,nil,nil)
    basePos = {-7, 1.38, 0}
    for key,value in pairs(expansions) do
        if value~=false and key~="LunaticExtra" then
            remeber = key
            WebRequest.get("http://66.70.189.147:8080/danmaku/"..key, function(a) webRequestCallback(a, key) end)
        end
    end
    Wait.condition(doEverything, waitCondition)
end

function closePanel(player, _, id)
    UI.setAttribute("expansionSelection", "active", false)
    UI.setAttribute("openButton", "active", true)
end

function openPanel(player, _, id)
    UI.setAttribute("expansionSelection", "active", true)
    UI.setAttribute("openButton", "active", false)
end

--# Turn Phase Tracker

function StringToBool(s) if s == "False" or s == "false" then return false else return true end end

function onPlayerTurnStart(_, _)
    UI.setAttribute("phaseTrackerButtonStart" , "isOn", true)
end

function phaseTrackerPhaseChange(Playerr, isOn, id)
    on = StringToBool(isOn)
    UI.setAttribute(id, "isOn", on)
    if on then
        local tempstring = "CALL LEATHER HE FUCKED UP SOMETHING" 
        if id == "phaseTrackerButtonStart"
            then tempstring = "Start of turn"
        elseif id == "phaseTrackerButtonIncident"
            then tempstring = "Incident Phase"
        elseif id == "phaseTrackerButtonDraw"
            then tempstring = "Draw Step"
        elseif id == "phaseTrackerButtonMain"
            then tempstring = "Main Phase"
        elseif id == "phaseTrackerButtonDiscard"
            then tempstring = "Discard Phase"
        elseif id == "phaseTrackerButtonEnd"
            then tempstring = "End of Turn"
        end
    broadcastToAll(tempstring, Playerr.color) end
end