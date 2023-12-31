{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-|
Module      : Camino
Description : Data models for travelling the Camino
Copyright   : (c) Doug Palmer, 2023
License     : MIT
Maintainer  : doug@charvolant.org
Stability   : experimental
Portability : POSIX

A camino consists of a graph of legs that can be assembled in various ways.
The legs run between two locations, each with possible accommodation and service options.

Generally, it is expected that these models will be read from JSON files.
-}
module Camino.Camino (
  Accommodation(..),
  AccommodationType(..),
  Camino(..),
  Fitness(..),
  LatLong(..),
  Leg(..),
  Location(..),
  LocationType(..),
  Palette(..),
  Penance(..),
  Route(..),
  Service(..),
  Sleeping(..),

  module Graph.Programming,

  accommodationName,
  accommodationType,
  accommodationServices,
  accommodationSleeping,
  caminoBbox,
  caminoLegRoute,
  caminoLocations,
  caminoRoute,
  defaultPalette,
  defaultRoute,
  defaultSRS,
  locationAccommodationTypes,
  placeholderLocation,
) where

import GHC.Generics (Generic)
import Data.Aeson
import Data.Text (Text, unpack, pack)
import Data.Colour (Colour)
import Data.Colour.Names
import Data.Colour.SRGB (sRGB24read, sRGB24show)
import Data.Maybe (catMaybes)
import qualified Data.Map as M (Map, (!), fromList, elems)
import qualified Data.Set as S (Set, empty, map, fromList, member)
import Data.Scientific (fromFloatDigits, toRealFloat)
import Data.List (find)
import Graph.Graph
import Graph.Programming

-- | The measure of penance.
-- |
-- | Currently, based a simple float that can be thought of as equivalent to hours spent walking.
data Penance = Reject -- ^ Unsustainable penance
 | Penance Float -- ^ Simple penance
 deriving (Show)

instance Semigroup Penance where
  Reject <> _ = Reject
  _ <> Reject = Reject
  p1@(Penance score1) <> p2@(Penance score2) = if p1 == mempty then p2 else if p2 == mempty then p1 else Penance (score1 + score2)

instance Monoid Penance where
  mempty = Penance 0.0

instance Score Penance where
  invalid = Reject

instance Eq Penance where
  Reject == Reject = True
  Reject == _ = False
  _ == Reject = False
  (Penance score1) == (Penance score2) = score1 == score2
    
instance Ord Penance where
  compare Reject Reject = EQ
  compare Reject _ = GT
  compare _ Reject = LT
  compare (Penance score1) (Penance score2) = compare score1 score2

instance FromJSON Penance where
   parseJSON (Number v) = do
     return (Penance $ toRealFloat v)
   parseJSON (String v) = do
     return (if v /= "reject" then error ("Expecting \"reject\" got " ++ show v) else Reject)
   parseJSON v = error ("Unable to parse penance object " ++ show v)

instance ToJSON Penance where
    toJSON Reject = String "reject"
    toJSON (Penance score') = Number $ fromFloatDigits score'

-- | Spatial reference system
type SRS = String

-- | The default SRS
defaultSRS :: SRS
defaultSRS = "WGS84" :: SRS

data LatLong = LatLong {
  latitude :: Double,
  longitude :: Double,
  srs :: SRS
} deriving (Show)

instance FromJSON LatLong where
  parseJSON (Object v) = do
    latitude' <- v .: "latitude"
    longitude' <- v .: "longitude"
    srs' <- v .:? "srs" .!= defaultSRS
    return LatLong { latitude = latitude', longitude = longitude', srs = srs' }
  parseJSON v = error ("Unable to parse lat/long object " ++ show v)

instance ToJSON LatLong where
  toJSON (LatLong latitude' longitude' srs') = object [ "latitude" .= latitude', "longitude" .= longitude', "srs" .= (if srs' == defaultSRS then Nothing else Just srs') ]

-- | Broad accommodation types
data AccommodationType = MunicipalAlbergue -- ^ A hostel run by local volunteers
  | PrivateAlbergue -- ^ A hostel run as a local business
  | GuestHouse -- ^ A generic guesthouse
  | House -- ^ An entire house or apartment for rent
  | Hotel -- ^ A dedicated hotel
  | Camping -- ^ Camping (with a tent or without, depending on what carried)
  deriving (Generic, Show, Eq, Ord)

instance FromJSON AccommodationType
instance ToJSON AccommodationType
instance FromJSONKey AccommodationType where
  fromJSONKey = genericFromJSONKey defaultJSONKeyOptions
instance ToJSONKey AccommodationType where
  toJSONKey = genericToJSONKey defaultJSONKeyOptions

-- | Services available in a location or accommodation
data Service = WiFi -- ^ Wireless internet available
  | Restaurant -- ^ Bar and/or Restaurant
  | Pharmacy -- ^ Pharmacy
  | Bank -- ^ Banking facilities, including an automated teller machine
  | BicycleRepair -- ^ Bicycle repair shop
  | Groceries -- ^ Convenience store or supermarket
  | Medical -- ^ Doctor, hospital or other healthcare
  | WashingMachine -- ^ Washing machine available
  | Dryer -- ^ Dryer or spin-dryer available
  | Handwash -- ^ Handwash laundry facilities
  | Kitchen -- ^ Kitchen facilities
  | Breakfast -- ^ Breakfast available
  | Dinner -- ^ Dinner available
  | Lockers -- ^ Lockers or cabinets
  | Accessible -- ^ Fitted for people with disabilities
  | Stables -- ^ Stabling for horses available
  | Pets -- ^ Pets allowed
  | BicycleStorage -- ^ Bicycle storage available
  | CampSite -- ^ Camping sites available
  | Bedlinen -- ^ Bedlinen provided
  | Towels -- ^ Towels provided
  | Pool -- ^ Swimming pool available
  | Heating -- ^ Heated building
  | Prayer -- ^ Community prayer/liturgy 
  | Train -- ^ Train station
  | Bus -- ^ Bus station
  deriving (Show, Generic, Eq, Ord)

instance FromJSON Service
instance ToJSON Service
instance FromJSONKey Service where
  fromJSONKey = genericFromJSONKey defaultJSONKeyOptions
instance ToJSONKey Service where
  toJSONKey = genericToJSONKey defaultJSONKeyOptions

-- | Sleeping/room arrangements available  
data Sleeping = Shared -- ^ Shared accommodation in a dormitory
  | Single -- ^ Single room
  | Double -- ^ Double room with shared bathroom
  | DoubleWC -- ^ Double room with a private bathroom
  | Triple -- ^ Triple room with shared bathroom
  | TripleWC -- ^ Triple room with private bathroom
  | Quadruple -- ^ Room for 4 with shared bathroom
  | QuadrupleWC -- ^ Room for 4 room with private bathroom
  | Mattress -- ^ Mattresses on the floor
  | SleepingBag -- ^ Own sleeping bag and mattress
  deriving (Show, Generic, Eq, Ord)

instance FromJSON Sleeping
instance ToJSON Sleeping

-- | Somewhere to stay at the end of a leg
data Accommodation =
  Accommodation Text AccommodationType (S.Set Service) (S.Set Sleeping) -- ^ Fully described accommodation
  | GenericAccommodation AccommodationType -- ^ Generic accommodation with default services, sleeping arrangements based on type
  deriving (Show)
  
accommodationName :: Accommodation -> Text
accommodationName (Accommodation name' _type _services _sleeping) = name'
accommodationName (GenericAccommodation type') = pack ("Generic " ++ show type')

accommodationType :: Accommodation -> AccommodationType
accommodationType (Accommodation _name type' _services _sleeping) = type'
accommodationType (GenericAccommodation type') = type'

accommodationServices :: Accommodation -> S.Set Service
accommodationServices (Accommodation _name _type services' _sleeping) = services'
accommodationServices (GenericAccommodation MunicipalAlbergue) = S.fromList [ Handwash ]
accommodationServices (GenericAccommodation PrivateAlbergue) = S.fromList [ Handwash, WiFi, Bedlinen, Towels ]
accommodationServices (GenericAccommodation GuestHouse) = S.fromList [ WiFi, Breakfast, Bedlinen, Towels ]
accommodationServices (GenericAccommodation House) = S.fromList [ WiFi, Bedlinen, Towels ]
accommodationServices (GenericAccommodation Hotel) = S.fromList [ WiFi, Breakfast, Dinner, Restaurant, Bedlinen, Towels ]
accommodationServices (GenericAccommodation _) = S.empty

accommodationSleeping :: Accommodation -> S.Set Sleeping
accommodationSleeping (Accommodation _name _type _services sleeping') = sleeping'
accommodationSleeping (GenericAccommodation MunicipalAlbergue) = S.fromList [ Shared ]
accommodationSleeping (GenericAccommodation PrivateAlbergue) = S.fromList [ Shared ]
accommodationSleeping (GenericAccommodation GuestHouse) = S.fromList [ Single, Double ]
accommodationSleeping (GenericAccommodation House) = S.fromList [ Single, Double ]
accommodationSleeping (GenericAccommodation Hotel) = S.fromList [ DoubleWC ]
accommodationSleeping (GenericAccommodation _) = S.fromList [ SleepingBag ]

instance FromJSON Accommodation where
   parseJSON t@(String _v) = do
     type' <- parseJSON t
     return $ GenericAccommodation type'
   parseJSON (Object v) = do
     name' <- v .: "name"
     type' <- v .: "type"
     services' <- v .: "services"
     sleeping' <- v .: "sleeping"
     return $ Accommodation name' type' services' sleeping'
   parseJSON v = error ("Unable to parse accomodation object " ++ show v)
instance ToJSON Accommodation where
    toJSON (Accommodation name' type' services' sleeping') =
      object [ "name" .= name', "type" .= type', "services" .= services', "sleeping" .= sleeping' ]
    toJSON (GenericAccommodation type' ) =
      toJSON type'
 
-- | Sleeping/room arrangements available  
data LocationType = Village -- ^ A village
   | Town -- ^ A town
   | City -- ^ A city
   | Bridge -- ^ A bridge
   | Intersection -- ^ An intersection
   | Poi -- ^ A generic point of interest
   deriving (Show, Generic, Eq, Ord)
 
instance FromJSON LocationType
instance ToJSON LocationType
     
-- | A location, usually a city/town/village that marks the start and end points of a leg
--   and which may have accomodation and other services available.
--   Locations form the vertexes on the travel graph
data Location = Location {
  locationID :: String,
  locationName :: Text,
  locationType :: LocationType,
  locationPosition :: Maybe LatLong,
  locationServices :: S.Set Service,
  locationAccommodation :: [Accommodation]
} deriving (Show)

instance FromJSON Location where
  parseJSON (String v) = do
    return $ placeholderLocation (unpack v)
  parseJSON (Object v) = do
    id' <- v .: "id"
    name' <- v .: "name"
    type' <- v .:? "type" .!= Poi
    position' <- v .:? "position"
    services' <- v .: "services"
    accommodation' <- v .: "accommodation"
    return Location { locationID = id', locationName = name', locationType = type', locationPosition = position', locationServices = services', locationAccommodation = accommodation' }
  parseJSON v = error ("Unable to parse location object " ++ show v)

instance ToJSON Location where
    toJSON (Location id' name' type' services' accommodation' position') =
      object [ "id" .= id', "name" .= name', "type" .= type', "position" .= position', "services" .= services', "accommodation" .= accommodation' ]

instance Vertex Location where
  identifier = locationID

instance Eq Location where
  a == b = locationID a == locationID b
  
instance Ord Location where
  a `compare` b = locationID a `compare` locationID b

-- | Create a placeholder for a location
placeholderLocation :: String -> Location
placeholderLocation ident = Location {
    locationID = ident,
    locationName = pack ("Placeholder for " ++ ident),
    locationType = Poi,
    locationPosition = Nothing,
    locationServices = S.empty,
    locationAccommodation = []
  }

-- | Get the accommodation types available at a location
--   These are ordered into enumeration order
locationAccommodationTypes :: Location -> S.Set AccommodationType
locationAccommodationTypes location = S.fromList $ map accommodationType (locationAccommodation location)

-- | A leg from one location to another.
--   Legs form the edges of a camino graph.
-- 
--   Legs have a total ascent and descent. 
--   These are usually assumed to be relatively lumpy and are grouped together for
--   time calculations
data Leg = Leg {
  legFrom :: Location, -- ^ The start location
  legTo :: Location, -- ^ The end location
  legDistance :: Float, -- ^ The distance between the start and end in kilometres
  legAscent :: Float, -- ^ The total ascent on the leg in metres
  legDescent :: Float -- ^ The total descent on the leg in metres
} deriving (Show)

instance FromJSON Leg where
    parseJSON (Object v) = do
      from' <- v .: "from"
      to' <- v .: "to"
      distance' <- v .: "distance"
      ascent' <- v .: "ascent"
      descent' <- v .: "descent"
      return Leg { legFrom = from', legTo = to', legDistance = distance', legAscent = ascent', legDescent = descent' }
    parseJSON v = error ("Unable to parse leg object " ++ show v)

instance ToJSON Leg where
    toJSON (Leg from' to' distance' ascent' descent') =
      object [ "from" .= locationID from', "to" .= locationID to', "distance" .= distance', "ascent" .= ascent', "descent" .= descent' ]

instance Edge Leg Location where
  source = legFrom
  target = legTo
  
-- | Ensure a leg has locations mapped correctly
normaliseLeg :: M.Map String Location -> Leg -> Leg
normaliseLeg locs (Leg from to distance ascent descent) =
  Leg { legFrom = locs M.! locationID from, legTo = locs M.! locationID to, legDistance = distance, legAscent = ascent, legDescent = descent }

-- | A palette, graphical styles to use for displaying information
data Palette = Palette {
  paletteColour :: Colour Double -- ^ The basic colour of the element
} deriving (Show)
      
instance FromJSON Palette where
  parseJSON (Object v) = do
    colour' <- v .: "colour"
    return Palette { paletteColour = sRGB24read colour' }
  parseJSON v = error ("Unable to parse palette object " ++ show v)

instance ToJSON Palette where
  toJSON (Palette colour') =
    object [ "colour" .= sRGB24show colour' ]

-- | A default palette for generic display
defaultPalette :: Palette
defaultPalette = Palette {
  paletteColour = yellow
}

-- | A route, a sub-section of the camino with graphical information
data Route = Route {
  routeID :: String, -- ^ An identifier for the route
  routeName :: Text, -- ^ The route name
  routeLocations :: S.Set Location, -- ^ The locations along the route
  routePalette :: Palette
} deriving (Show)

instance FromJSON Route where
    parseJSON (Object v) = do
      id' <- v .: "id"
      name' <- v .: "name"
      locations' <- v .: "locations"
      palette' <- v .: "palette"
      return Route { routeID = id', routeName = name', routeLocations = locations', routePalette = palette' }
    parseJSON v = error ("Unable to parse route object " ++ show v)

instance ToJSON Route where
    toJSON (Route id' name' locations' palette') =
      object [ "id" .= id', "name" .= name', "locations" .= S.map locationID locations', "palette" .= palette' ]

-- | Ensure that the route locations are mapped properly
normaliseRoute :: M.Map String Location -> Route -> Route
normaliseRoute locs route = route { routeLocations = S.map (\l -> locs M.! locationID l) (routeLocations route)}

-- | A way, consisting of a number of legs with a start and end
--   The purpose of the Camino Planner is to divide a camino into 
data Camino = Camino {
  locations :: M.Map String Location, -- ^ The camino locations
  legs :: [Leg], -- ^ The legs between locations
  routes :: [Route], -- ^ Named sub-routes
  palette :: Palette -- ^ The default palette
} deriving (Show)

instance FromJSON Camino where
  parseJSON (Object v) = do
    locs <- v .: "locations"
    let locMap = M.fromList $ map (\w -> (locationID w, w)) locs
    legs' <- v .: "legs"
    let legs'' = map (normaliseLeg locMap) legs'
    routes' <- v .: "routes"
    let routes'' = map (normaliseRoute locMap) routes'
    palette' <- v .: "palette"
    return Camino { locations = locMap, legs = legs'', routes = routes'', palette = palette' }
  parseJSON v = error ("Unable to parse camino object " ++ show v)


instance ToJSON Camino where
  toJSON (Camino locations' legs' routes' palette') =
    object [ "locations" .= (M.elems locations'), "legs" .= legs', "routes" .= routes', "palette" .= palette' ]

instance Graph Camino Leg Location where
  vertex camino vid = (locations camino) M.! vid
  edge camino loc1 loc2 = find (\l -> loc1 == legFrom l && loc2 == legTo l) (legs camino)
  incoming camino location = filter (\l -> location == legTo l) (legs camino)
  outgoing camino location = filter (\l -> location == legFrom l) (legs camino)

-- | Get a list of locations for the camino
caminoLocations :: Camino -- ^ The camino
  -> [Location] -- ^ The list of locations
caminoLocations camino = M.elems $ locations camino

-- | Get a bounding box for the camino
caminoBbox :: Camino -- ^ The entire camino
 -> (LatLong, LatLong) -- ^ The bouding box (top-left, bottom-right)
caminoBbox camino = (LatLong (maximum lats) (minimum longs) defaultSRS, LatLong (minimum lats) (maximum longs) defaultSRS)
  where
    positions = catMaybes $ map locationPosition $ M.elems $ locations camino
    lats = map latitude positions
    longs = map longitude positions
  

-- | The default route for a camino
defaultRoute :: Camino -> Route
defaultRoute camino = Route { routeID = "default", routeName = "Default", routeLocations = S.empty, routePalette = palette camino }

-- | Choose a route for a location
--   If the location isn't on a specific route, then the default route is returned
caminoRoute :: Camino -- ^ The camino being interrogated
  -> Location -- ^ The location to test
  -> Route -- ^ The route that the location is on
caminoRoute camino location = let
    route = find (\r -> S.member location (routeLocations r)) (routes camino)
  in
    maybe (defaultRoute camino) id route
   
-- | Choose a route for a leg
--   If the leg isn't on a specific route, then the default route is returned
caminoLegRoute :: Camino -- ^ The camino being interrogated
  -> Leg -- ^ The location to test
  -> Route -- ^ The route that the location is on
caminoLegRoute camino leg = let
    from' = legFrom leg
    to' = legTo leg
    route = find (\r -> S.member from' (routeLocations r) || S.member to' (routeLocations r)) (routes camino)
  in
    maybe (defaultRoute camino) id route
 
-- | An approximate level of fitness.
-- 
--   In the Tranter corrections, the levels of fitness are defined by
--   The number of minutes it takes to climb 1000ft (305m) over half a mile (805m)
--   Or a slope of approximately 1 in 2.5

data Fitness = SuperFit -- ^ 15 minutes for 1000ft over 1/2 a mile
  | VeryFit -- ^ 20 minutes for 1000ft over 1/2 a mile
  | Fit -- ^ 25 minutes for 1000ft over 1/2 a mile
  | Normal -- ^ 30 minutes for 1000ft over 1/2 a mile
  | Unfit -- ^ 40 minutes for 1000ft over 1/2 a mile 
  | VeryUnfit -- ^ 50 minutes for 1000ft over 1/2 a mile
  deriving (Generic, Show, Eq, Enum)

instance FromJSON Fitness
instance ToJSON Fitness
