#!/usr/bin/env python3
# ============================================================================
# BIMTRA HELICOPTER DATA ANALYSIS (RMSP ONLY)
# Filter for valid helicopters and routes where BOTH origin AND destination are in RMSP
# ============================================================================
# %%
import os
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from datetime import datetime, timedelta
import warnings

warnings.filterwarnings('ignore')

# Set style for plots
sns.set_style("whitegrid")
plt.rcParams['figure.figsize'] = (12, 6)
plt.rcParams['font.size'] = 10

print("\n========== BIMTRA HELICOPTER DATA ANALYSIS (RMSP ONLY) ==========\n")

# ============================================================================
# 1. LOAD DATA
# ============================================================================
print("Step 1: Loading BIMTRA data...")

file_path = "data/raw/bimtra/BIMTRA.csv"

if not os.path.exists(file_path):
    raise FileNotFoundError(f"File not found: {file_path}")

df = pd.read_csv(file_path)

print(f"  Loaded: {len(df)} movement records")
print(f"  Columns: {list(df.columns)}\n")

initial_rows = len(df)

# Parse datetime column
df['dhmovreal'] = pd.to_datetime(df['dhmovreal'], errors='coerce')

# Find date range
valid_dates = df[df['dhmovreal'].notna()]
if len(valid_dates) > 0:
    print(f"  Date range: {valid_dates['dhmovreal'].min()} to {valid_dates['dhmovreal'].max()}\n")

# ============================================================================
# 2. DATA QUALITY ASSESSMENT
# ============================================================================
print("Step 2: Initial data quality assessment...\n")

print("Initial data info:")
print(f"  Total records: {len(df)}")
print(f"  Missing values (key columns):")
print(f"    dhmovreal: {df['dhmovreal'].isna().sum()}")
print(f"    matricula: {df['matricula'].isna().sum()}")
print(f"    tipoaeronave: {df['tipoaeronave'].isna().sum()}")
print(f"    deparr: {df['deparr'].isna().sum()}\n")

print("Unique values in key columns:")
print(f"  Aircraft types (tipoaeronave): {df['tipoaeronave'].nunique()}")
print(f"  Event types (deparr): {df['deparr'].unique()}")
print(f"  Unique aircraft (matricula): {df['matricula'].nunique()}\n")

# ============================================================================
# 3. FILTER FOR VALID HELICOPTERS AND HELIPORTS
# ============================================================================
print("Step 3: Filtering for valid helicopter data...\n")

# Define valid heliports (RMSP only - 285 facilities)
valid_heliports = {
    'SBGR', 'SBMT', 'SBSP', 'SNIA', 'SNN2', 'SSFR', 'SIPI', 'SNAZ', 'SDBC', 'SWAB',
    'SIDH', 'SDEI', 'SWKM', 'SJZY', 'SDJK', 'SDTM', 'SJUE', 'SWEG', 'SDEG', 'SNTN',
    'SIF4', 'SDWS', 'SIH7', 'SSOV', 'SNMY', 'SJMC', 'SDZT', 'SWDJ', 'SWCK', 'SWTE',
    'SSAW', 'SDII', 'SJYB', 'SNGZ', 'SDEU', 'SWCX', 'SJON', 'SJAO', 'SSZJ', 'SIAV',
    'SIE7', 'SSIL', 'SJUN', 'SDEY', 'SIPZ', 'SWUP', 'SSEJ', 'SDEF', 'SDQW', 'SDXP',
    'SWGM', 'SDAC', 'SDGO', 'SJ9Q', 'SIGK', 'SNRE', 'SITK', 'SNDM', 'SILX', 'SJES',
    'SDQV', 'SDOH', 'SSUN', 'SNNI', 'SDZE', 'SWUS', 'SJ3W', 'SJEY', 'SBQY', 'SIKC',
    'SJAM', 'SJSZ', 'SWHW', 'SDEW', 'SNJS', 'SNWW', 'SDHB', 'SDGZ', 'SSUB', 'SSHJ',
    'SDHG', 'SICG', 'SDLF', 'SINE', 'SJ26', 'SJIW', 'SIIW', 'SDPS', 'SJRM', 'SDVV',
    'SSLH', 'SWOP', 'SIEE', 'SJQH', 'SDMZ', 'SJII', 'SWQV', 'SNQH', 'SDGE', 'SIBM',
    'SSXE', 'SNVT', 'SDGG', 'SWSK', 'SJXP', 'SBOP', 'SJBP', 'SDOT', 'SS4B', 'SDMT',
    'SIBG', 'SDAW', 'SDSZ', 'SWHH', 'SDNR', 'SSZE', 'SDBH', 'SNBQ', 'SDBM', 'SITO',
    'SDGS', 'SDNN', 'SDDH', 'SJBG', 'SN66', 'SSOA', 'SIIR', 'SNDK', 'SDWB', 'SDYA',
    'SDUI', 'SNSQ', 'SSQY', 'SDHT', 'SDIA', 'SDCV', 'SI8S', 'SJWC', 'SI74', 'SDVU',
    'SDKD', 'SDNP', 'SIYZ', 'SIGO', 'SDFW', 'SDEL', 'SIRZ', 'SWHX', 'SSCS', 'SDMN',
    'SIOD', 'SDFM', 'SIHD', 'SIBS', 'SJWZ', 'SIMM', 'SIXS', 'SJBO', 'SDTJ', 'SDTG',
    'SIBB', 'SDKT', 'SIDA', 'SDTC', 'SIJF', 'SDEA', 'SDOF', 'SIYU', 'SDIW', 'SJXK',
    'SS6Y', 'SJOZ', 'SDFV', 'SJFC', 'SDKG', 'SSQX', 'SJNS', 'SIR6', 'SJPB', 'SNIL',
    'SJWJ', 'SIBH', 'SSUH', 'SSVH', 'SWMF', 'SIRY', 'SDHV', 'SIOW', 'SNMP', 'SSYH',
    'SDHW', 'SDHI', 'SDAP', 'SDDG', 'SIHK', 'SJRQ', 'SDJU', 'SJSL', 'SSPQ', 'SDKY',
    'SDOC', 'SWNI', 'SDAT', 'SDKM', 'SNID', 'SNQC', 'SDSX', 'SDPL', 'SDJP', 'SIJX',
    'SDXQ', 'SNLR', 'SDTU', 'SWTF', 'SSKL', 'SDGW', 'SJDD', 'SIKT', 'SJ7Y', 'SIJD',
    'SJRZ', 'SSXK', 'SDYZ', 'SWEL', 'SIRO', 'SJMG', 'SDLB', 'SDUJ', 'SJEB', 'SNSZ',
    'SIUD', 'SIQM', 'SILF', 'SJEI', 'SILK', 'SIYT', 'SDPM', 'SDPK', 'SDPT', 'SD6M',
    'SD6Q', 'SD6R', 'SDPO', 'SSWD', 'SIKF', 'SJTD', 'SIDE', 'SDBF', 'SDVR', 'SJGM',
    'SDBR', 'SDTN', 'SSUF', 'SDJW', 'SDKV', 'SWOU', 'SIGV', 'SNPH', 'SNRW', 'SDRB',
    'SIGZ', 'SIMD', 'SWRV', 'SDYV', 'SDZR', 'SN2Z', 'SJZU', 'SDHQ', 'SWYD', 'SDDS',
    'SDSN', 'SDCY', 'SWNX', 'SD3C', 'SJTV', 'SJTY', 'SIIH', 'SD2H', 'SD3T', 'SSQV',
    'SDEZ', 'SILV', 'SJVC', 'SI49', 'SDWT', 'SDRN', 'SDON', 'SIVC'
}

print(f"  Valid RMSP heliports defined: {len(valid_heliports)}\n")

# Define valid helicopter equipment types
helicopter_base_types = [
    'A109', 'A119', 'A129', 'A139', 'A149', 'A169', 'A189', 'A2RT', 'A600', 'AC31', 'AC33', 'ALH', 'ALO2', 'ALO3', 'ANST',
    'AS15', 'AS32', 'AS3B', 'AS35', 'AS50', 'AS55', 'AS65',
    'B06', 'B06T', 'B105', 'B150', 'B212', 'B214', 'B222', 'B230', 'B305', 'B407', 'B412', 'B427', 'B429', 'B430', 'B47G', 'B47J', 'B47T', 'B505', 'B525',
    'BABY', 'BK17', 'BRB2', 'BSTP',
    'CH12', 'CH14', 'CH7', 'CHIF', 'COMU',
    'DJIN', 'DRAG', 'DYH2', 'DYH3',
    'EC20', 'EC25', 'EC30', 'EC35', 'EC45', 'EC53', 'EC55', 'EC75', 'EGL3', 'EH10', 'ELTO', 'EN28', 'EN48', 'ES11', 'EXEC', 'EXEJ', 'EXPL',
    'FH11', 'FREL',
    'G2CA', 'GAZL',
    'H12T', 'H125', 'H160', 'H2', 'H21', 'H269', 'H43A', 'H43B', 'H46', 'H47', 'H500', 'H53', 'H53S', 'H60', 'H64', 'HSMT', 'HUCO', 'HX2',
    'IS2',
    'JAG2',
    'K126', 'K209', 'K226', 'KA25', 'KA26', 'KA27', 'KA50', 'KA52', 'KA62', 'KH4', 'KMAX',
    'LAMA', 'LCH', 'LR2T', 'LYNX',
    'M74', 'MD52', 'MD60', 'MH20',
    'MI10', 'MI14', 'MI2', 'MI24', 'MI26', 'MI28', 'MI34', 'MI38', 'MI4', 'MI6', 'MI8',
    'NA40', 'NH90',
    'OH1',
    'PHIL', 'PSW4', 'PUMA',
    'R22', 'R4', 'R44', 'R66', 'RMOU', 'RP1', 'RVAL',
    'S274', 'S278', 'S285', 'S330', 'S360', 'S434', 'S51', 'S52', 'S55P', 'S55T', 'S58P', 'S58T', 'S61', 'S61R', 'S62', 'S64', 'S65C', 'S70', 'S76', 'S92', 'S97',
    'SB1', 'SCOR', 'SCOU', 'SH09', 'SH4', 'SK76', 'SUCO', 'SURN', 'SYCA',
    'TIGR',
    'UH1', 'UH12', 'UH1Y', 'ULTS',
    'V500',
    'W3', 'WASP', 'WESX',
    'WZ10',
    'X2', 'X3', 'X49',
    'YNHL',
    'ZA6', 'ZEFR'
]

# Create full list with and without /L suffix
valid_helicopter_equipment = []
for heli in helicopter_base_types:
    valid_helicopter_equipment.append(heli)
    valid_helicopter_equipment.append(f"{heli}/L")

# Extract base equipment type (without /L suffix)
df['Equipment_Base'] = df['tipoaeronave'].fillna('').str.split('/').str[0]

# Check which equipment types are in the data
print("Unique equipment types in data:")
unique_equipment = df['Equipment_Base'].unique()
print(f"  Found {len(unique_equipment)} types: {sorted([x for x in unique_equipment if x])}\n")

# Filter for valid helicopter equipment
df_filtered = df[df['Equipment_Base'].isin(valid_helicopter_equipment)].copy()

rows_removed = initial_rows - len(df_filtered)
removal_percentage = (rows_removed / initial_rows) * 100

print(f"Helicopter filtering:")
print(f"  Valid helicopters found: {len(df_filtered)}")
print(f"  Invalid/other aircraft removed: {rows_removed} ({removal_percentage:.2f}%)\n")

# ============================================================================
# 4. DATA QUALITY VALIDATION
# ============================================================================
print("Step 4: Data quality validation...\n")

records_before_validation = len(df_filtered)

# Remove rows with missing critical values
missing_before = len(df_filtered)
df_filtered = df_filtered.dropna(subset=['dhmovreal', 'deparr', 'tipoaeronave', 'adpartida', 'addestino'])
missing_removed = missing_before - len(df_filtered)

if missing_removed > 0:
    print(f"  Records with missing critical columns: {missing_removed}")

# Validate event types
invalid_events_before = len(df_filtered)
valid_events = ['D', 'A']  # D for Departure, A for Arrival
df_filtered = df_filtered[df_filtered['deparr'].isin(valid_events)]
invalid_events_removed = invalid_events_before - len(df_filtered)

if invalid_events_removed > 0:
    print(f"  Records with invalid event types: {invalid_events_removed}")

# Remove duplicates (same aircraft, same time, same event)
duplicates_before = len(df_filtered)
df_filtered = df_filtered.drop_duplicates(subset=['dhmovreal', 'matricula', 'deparr'], keep='first')
duplicates_removed = duplicates_before - len(df_filtered)

if duplicates_removed > 0:
    print(f"  Duplicate records removed: {duplicates_removed}")

total_removed = missing_removed + invalid_events_removed + duplicates_removed
print(f"\nTotal records removed in validation: {total_removed}")
print(f"After validation: {len(df_filtered)} records retained\n")

# ============================================================================
# 5. DETECT AND REMOVE NOISY DATA (RMSP ONLY)
# ============================================================================
print("Step 5: Detecting and removing noisy data (RMSP-only routes)...\n")

# RMSP-ONLY FILTER: Keep flights where BOTH origin AND destination are in valid RMSP heliports
df_filtered['is_valid_route'] = (
    (df_filtered['adpartida'].notna()) & 
    (df_filtered['addestino'].notna()) &
    (df_filtered['adpartida'] != df_filtered['addestino']) &
    ((df_filtered['adpartida'].isin(valid_heliports)) & (df_filtered['addestino'].isin(valid_heliports)))
)

invalid_routes = (~df_filtered['is_valid_route']).sum()
df_filtered = df_filtered[df_filtered['is_valid_route']].copy()

print(f"Routes removed (not RMSP-only): {invalid_routes}")
print(f"Records after RMSP-only filtering: {len(df_filtered)}\n")

# ============================================================================
# 6. FILTER FOR DEPARTURES ONLY
# ============================================================================
print("Step 6: Filtering for departures only...\n")

# Show movement breakdown before filtering
arrivals = len(df_filtered[df_filtered['deparr'] == 'A'])
departures_before = len(df_filtered[df_filtered['deparr'] == 'D'])

print("Movement Breakdown (before DEP filter):")
print(f"  Total records: {len(df_filtered)}")
print(f"  Departures (D): {departures_before}")
print(f"  Arrivals (A): {arrivals}\n")

# Filter for departures only - this becomes the main dataset for all statistics
df_departures = df_filtered[df_filtered['deparr'] == 'D'].copy()

# Add Equipment_Base column
df_departures['Equipment_Base'] = df_departures['tipoaeronave'].str.split('/').str[0]

print(f"After filtering for departures: {len(df_departures)} records retained\n")

# ============================================================================
# 7. EXTRACT DATE AND TIME INFORMATION
# ============================================================================
print("Step 7: Extracting date and time information...\n")

df_departures['Date'] = df_departures['dhmovreal'].dt.date
df_departures['Hour'] = df_departures['dhmovreal'].dt.hour
df_departures['DayOfWeek'] = df_departures['dhmovreal'].dt.day_name()
df_departures['Month'] = df_departures['dhmovreal'].dt.month
df_departures['Month_Name'] = df_departures['dhmovreal'].dt.strftime('%B')

# Sort by timestamp
df_departures = df_departures.sort_values('dhmovreal')
print(f"Date range: {df_departures['Date'].min()} to {df_departures['Date'].max()}\n")

# ============================================================================
# 8. GENERATE DAILY STATISTICS
# ============================================================================
print("Step 8: Generating daily statistics...\n")

# Calculate daily statistics
daily_stats = df_departures.groupby('Date').agg({
    'matricula': 'nunique',  # Number of unique aircraft
    'dhmovreal': ['size', 'min', 'max'],  # Count, first and last departure
    'Equipment_Base': 'nunique'  # Number of different helicopter types
}).reset_index()

# Flatten column names
daily_stats.columns = ['Date', 'Unique_Aircraft', 'Departures', 'First_Movement', 'Last_Movement', 'Helicopter_Types']

# Add day of week
daily_stats['DayOfWeek'] = pd.to_datetime(daily_stats['Date']).dt.day_name()

print("Daily Statistics Summary:")
print(f"  Date range: {daily_stats['Date'].min()} to {daily_stats['Date'].max()}")
print(f"  Number of operational days: {len(daily_stats)}")
print(f"  Days with departures: {daily_stats['Date'].notna().sum()}\n")

# ============================================================================
# 9. CALCULATE AGGREGATED STATISTICS
# ============================================================================
print("Step 9: Calculating aggregated statistics...\n")

# Daily flights statistics
daily_statistics = {
    'Max_Flights_Per_Day': daily_stats['Departures'].max(),
    'Min_Flights_Per_Day': daily_stats['Departures'].min(),
    'Mean_Flights_Per_Day': daily_stats['Departures'].mean(),
    'Median_Flights_Per_Day': daily_stats['Departures'].median(),
    'Std_Dev_Flights': daily_stats['Departures'].std(),
    'Total_Flights': daily_stats['Departures'].sum(),
    'Avg_Aircraft_Per_Day': daily_stats['Unique_Aircraft'].mean(),
    'Max_Aircraft_Per_Day': daily_stats['Unique_Aircraft'].max(),
}

print("Flight Statistics (RMSP-only routes, based on departures):")
print(f"  Total departures: {daily_statistics['Total_Flights']:.0f}")
print(f"  Mean flights per day: {daily_statistics['Mean_Flights_Per_Day']:.2f}")
print(f"  Median flights per day: {daily_statistics['Median_Flights_Per_Day']:.0f}")
print(f"  Maximum flights per day: {daily_statistics['Max_Flights_Per_Day']:.0f}")
print(f"  Minimum flights per day: {daily_statistics['Min_Flights_Per_Day']:.0f}")
print(f"  Std deviation: {daily_statistics['Std_Dev_Flights']:.2f}")
print(f"  Days with operations: {len(daily_stats)}")
print(f"  Average aircraft per day: {daily_statistics['Avg_Aircraft_Per_Day']:.2f}\n")

# Aircraft statistics
aircraft_stats = df_departures.groupby('matricula').agg({
    'dhmovreal': 'count',  # Total departures
    'tipoaeronave': 'first',  # Equipment type
    'adpartida': lambda x: x.nunique(),  # Unique origins
    'addestino': lambda x: x.nunique(),  # Unique destinations
}).reset_index()

aircraft_stats.columns = ['Aircraft', 'Departures', 'Equipment', 'Unique_Origins', 'Unique_Destinations']
aircraft_stats = aircraft_stats.sort_values('Departures', ascending=False)

print("Top Aircraft by Departures (RMSP-only):")
print(aircraft_stats.head(10).to_string(index=False))
print()

# Equipment statistics
equipment_stats = df_departures.groupby('Equipment_Base').agg({
    'matricula': 'nunique',  # Number of aircraft
    'dhmovreal': 'count',      # Total departures
}).reset_index()

equipment_stats.columns = ['Equipment', 'Number_of_Aircraft', 'Departures']
equipment_stats = equipment_stats.sort_values('Departures', ascending=False)

print("Helicopter Equipment Statistics (RMSP-only, by Departures):")
print(equipment_stats.to_string(index=False))
print()

# ============================================================================
# 10. HOURLY STATISTICS
# ============================================================================
print("Step 10: Analyzing hourly patterns...\n")

hourly_stats = df_departures.groupby('Hour').size().reset_index(name='Total_Departures')
# Calculate mean departures per hour across all operational days
hourly_stats['Mean_Departures_Per_Day'] = hourly_stats['Total_Departures'] / len(daily_stats)

print("Peak operating hours (total, RMSP-only):")
print(hourly_stats.nlargest(5, 'Total_Departures')[['Hour', 'Total_Departures', 'Mean_Departures_Per_Day']].to_string(index=False))
print()

# ============================================================================
# 11. ROUTE STATISTICS
# ============================================================================
print("Step 11: Analyzing routes...\n")

routes = df_departures.groupby(['adpartida', 'addestino']).agg({
    'dhmovreal': 'count',
    'matricula': 'nunique'
}).reset_index()

routes.columns = ['Origin', 'Destination', 'Departures', 'Unique_Aircraft']
routes = routes.sort_values('Departures', ascending=False)

print(f"Total unique RMSP-only routes: {len(routes)}")
print("\nTop 10 busiest RMSP-only routes (by departures):")
print(routes.head(10).to_string(index=False))
print()

# ============================================================================
# 11B. HELIPORT-LEVEL ANALYSIS (DEMAND BY FACILITY)
# ============================================================================
print("Step 11B: Analyzing heliport-level demand...\n")

# Analyze outbound traffic (departures from heliport)
outbound = df_departures.groupby('adpartida').agg({
    'dhmovreal': 'count',
    'matricula': 'nunique'
}).reset_index()
outbound.columns = ['Heliport', 'Outbound_Flights', 'Outbound_Aircraft']

# Analyze inbound traffic (arrivals at heliport - destinations in departure records)
inbound = df_departures.groupby('addestino').agg({
    'dhmovreal': 'count',
    'matricula': 'nunique'
}).reset_index()
inbound.columns = ['Heliport', 'Inbound_Flights', 'Inbound_Aircraft']

# Merge outbound and inbound data
heliport_stats = outbound.merge(inbound, on='Heliport', how='outer').fillna(0)

# Convert aircraft counts to integer
heliport_stats['Outbound_Flights'] = heliport_stats['Outbound_Flights'].astype(int)
heliport_stats['Inbound_Flights'] = heliport_stats['Inbound_Flights'].astype(int)
heliport_stats['Outbound_Aircraft'] = heliport_stats['Outbound_Aircraft'].astype(int)
heliport_stats['Inbound_Aircraft'] = heliport_stats['Inbound_Aircraft'].astype(int)

# Calculate combined metrics
heliport_stats['Total_Flights'] = heliport_stats['Outbound_Flights'] + heliport_stats['Inbound_Flights']
heliport_stats['Total_Aircraft'] = heliport_stats['Outbound_Aircraft'] + heliport_stats['Inbound_Aircraft']

# Calculate percentages of total traffic
total_flights = heliport_stats['Total_Flights'].sum()
heliport_stats['Percentage_Total'] = (heliport_stats['Total_Flights'] / total_flights) * 100

# Sort by total flights
heliport_stats = heliport_stats.sort_values('Total_Flights', ascending=False)

print(f"Total active heliports: {len(heliport_stats)}")
print(f"Total flight operations (both directions): {heliport_stats['Total_Flights'].sum():.0f}\n")

print("Top 15 heliports by total demand (outbound + inbound):")
print(heliport_stats.head(15)[['Heliport', 'Outbound_Flights', 'Inbound_Flights', 'Total_Flights', 'Percentage_Total']].to_string(index=False))
print()

print("Top 10 heliports by outbound traffic:")
heliport_outbound = heliport_stats.nlargest(10, 'Outbound_Flights')[['Heliport', 'Outbound_Flights', 'Outbound_Aircraft']]
print(heliport_outbound.to_string(index=False))
print()

print("Top 10 heliports by inbound traffic:")
heliport_inbound = heliport_stats.nlargest(10, 'Inbound_Flights')[['Heliport', 'Inbound_Flights', 'Inbound_Aircraft']]
print(heliport_inbound.to_string(index=False))
print()

# ============================================================================
# 12. SAVE FILTERED DATA AND STATISTICS
# ============================================================================
print("Step 12: Saving filtered data and statistics...\n")

output_dir = "output/helicopter_analysis_bimtra_rmsp_only"
if not os.path.exists(output_dir):
    os.makedirs(output_dir, exist_ok=True)

# Save departure data
df_departures.to_csv(f"{output_dir}/BIMTRA_RMSP_Only_departures.csv", index=False)
print(f"  Saved: BIMTRA_RMSP_Only_departures.csv ({len(df_departures)} records)")

# Save daily statistics
daily_stats.to_csv(f"{output_dir}/BIMTRA_RMSP_Only_daily_statistics.csv", index=False)
print(f"  Saved: BIMTRA_RMSP_Only_daily_statistics.csv ({len(daily_stats)} days)")

# Save aircraft statistics
aircraft_stats.to_csv(f"{output_dir}/BIMTRA_RMSP_Only_aircraft_statistics.csv", index=False)
print(f"  Saved: BIMTRA_RMSP_Only_aircraft_statistics.csv")

# Save equipment statistics
equipment_stats.to_csv(f"{output_dir}/BIMTRA_RMSP_Only_equipment_statistics.csv", index=False)
print(f"  Saved: BIMTRA_RMSP_Only_equipment_statistics.csv")

# Save route statistics
routes.to_csv(f"{output_dir}/BIMTRA_RMSP_Only_route_statistics.csv", index=False)
print(f"  Saved: BIMTRA_RMSP_Only_route_statistics.csv ({len(routes)} routes)")

# Save heliport statistics
heliport_stats.to_csv(f"{output_dir}/BIMTRA_RMSP_Only_heliport_statistics.csv", index=False)
print(f"  Saved: BIMTRA_RMSP_Only_heliport_statistics.csv ({len(heliport_stats)} heliports)\n")

# ============================================================================
# 12B. GENERATE OD MAPPING DATA WITH COORDINATES
# ============================================================================
print("Step 12B: Generating OD mapping data with heliport coordinates...\n")

# Load heliports from complete coordinates database
heliports_dict = {}
try:
    heliports_csv = "data/processed/heliports_complete_with_coordinates.csv"
    if os.path.exists(heliports_csv):
        heliports_df = pd.read_csv(heliports_csv)
        for _, row in heliports_df.iterrows():
            heliports_dict[row['code']] = {
                'name': row['heliport_name'],
                'lat': row['latitude'],
                'lon': row['longitude']
            }
        print(f"  Loaded {len(heliports_dict)} heliports from complete database\n")
    else:
        # Fallback to original heliports database if complete database not available
        heliports_csv = "data/processed/heliports.csv"
        if os.path.exists(heliports_csv):
            heliports_df = pd.read_csv(heliports_csv)
            for _, row in heliports_df.iterrows():
                heliports_dict[row['code']] = {
                    'name': row['heliport_name'],
                    'lat': row['latitude'],
                    'lon': row['longitude']
                }
            print(f"  Loaded {len(heliports_dict)} heliports from fallback database\n")
        else:
            print(f"  Heliports CSV not found at {heliports_csv}\n")
except Exception as e:
    print(f"  Warning: Could not load heliports CSV - {e}\n")

# Generate OD pairs from departures
od_pairs = df_departures.groupby(['adpartida', 'addestino']).agg({
    'matricula': 'nunique',  # Unique aircraft
    'dhmovreal': 'count'     # Number of departures
}).reset_index()

od_pairs.columns = ['Origin', 'Destination', 'Unique_Aircraft', 'Departures']

# Add coordinates from heliports dictionary
od_pairs['Origin_Lat'] = od_pairs['Origin'].map(lambda x: heliports_dict.get(x, {}).get('lat'))
od_pairs['Origin_Lon'] = od_pairs['Origin'].map(lambda x: heliports_dict.get(x, {}).get('lon'))
od_pairs['Origin_Name'] = od_pairs['Origin'].map(lambda x: heliports_dict.get(x, {}).get('name', x))

od_pairs['Dest_Lat'] = od_pairs['Destination'].map(lambda x: heliports_dict.get(x, {}).get('lat'))
od_pairs['Dest_Lon'] = od_pairs['Destination'].map(lambda x: heliports_dict.get(x, {}).get('lon'))
od_pairs['Dest_Name'] = od_pairs['Destination'].map(lambda x: heliports_dict.get(x, {}).get('name', x))

# Calculate percentages
total_departures = od_pairs['Departures'].sum()
od_pairs['Percentage'] = (od_pairs['Departures'] / total_departures) * 100

# Sort by departures
od_pairs = od_pairs.sort_values('Departures', ascending=False)

# Save ALL OD pairs (complete dataset)
od_pairs.to_csv(f"{output_dir}/BIMTRA_RMSP_Only_od_mapping_data_all.csv", index=False)
print(f"  Saved: BIMTRA_RMSP_Only_od_mapping_data_all.csv ({len(od_pairs)} routes, {od_pairs['Departures'].sum()} total departures)")

# Save only OD pairs with valid coordinates (for mapping)
od_complete = od_pairs.dropna(subset=['Origin_Lat', 'Origin_Lon', 'Dest_Lat', 'Dest_Lon']).copy()
od_complete.to_csv(f"{output_dir}/BIMTRA_RMSP_Only_od_mapping_data_complete.csv", index=False)

# Identify routes missing coordinates
routes_missing_coords = od_pairs[od_pairs[['Origin_Lat', 'Origin_Lon', 'Dest_Lat', 'Dest_Lon']].isna().any(axis=1)].copy()
departures_missing_coords = routes_missing_coords['Departures'].sum()

print(f"  Saved: BIMTRA_RMSP_Only_od_mapping_data_complete.csv ({len(od_complete)} routes with coordinates, {od_complete['Departures'].sum()} departures)\n")

print("OD Mapping Summary (RMSP-Only):")
print(f"  Total unique RMSP-only routes: {len(od_pairs)}")
print(f"  Total departures (all RMSP-only routes): {od_pairs['Departures'].sum():.0f}")
print(f"  Routes with known coordinates: {len(od_complete)} ({(len(od_complete)/len(od_pairs)*100):.1f}%)")
print(f"  Departures with known coordinates: {od_complete['Departures'].sum():.0f} ({(od_complete['Departures'].sum()/od_pairs['Departures'].sum()*100):.1f}%)")
print(f"\n  Routes MISSING coordinates: {len(routes_missing_coords)}")
print(f"  Departures from routes missing coordinates: {departures_missing_coords:.0f}")
if len(routes_missing_coords) > 0:
    print(f"\n  Top routes missing from visualization (missing coordinates):")
    print(routes_missing_coords.head(10)[['Origin', 'Destination', 'Departures']].to_string(index=False))
print(f"\n  Top 5 RMSP-only routes with coordinates:")
print(od_complete.head(5)[['Origin', 'Destination', 'Departures', 'Percentage']].to_string(index=False))
print()

# ============================================================================
# 13. GENERATE VISUALIZATIONS
# ============================================================================
print("Step 13: Generating visualizations...\n")

visualization_dir = f"{output_dir}/visualizations"
if not os.path.exists(visualization_dir):
    os.makedirs(visualization_dir, exist_ok=True)

# Plot 1: Daily flights over time
fig, ax = plt.subplots(figsize=(14, 6))
ax.plot(pd.to_datetime(daily_stats['Date']), daily_stats['Departures'], 
        marker='o', linestyle='-', linewidth=2, markersize=4, color='steelblue', alpha=0.7)
ax.fill_between(pd.to_datetime(daily_stats['Date']), daily_stats['Departures'], 
                alpha=0.3, color='steelblue')
ax.axhline(daily_statistics['Mean_Flights_Per_Day'], color='red', linestyle='--', 
           label=f'Mean: {daily_statistics["Mean_Flights_Per_Day"]:.1f}')
ax.set_xlabel('Date')
ax.set_ylabel('Number of Flight Operations')
ax.set_title('BIMTRA (RMSP-Only): Daily Helicopter Flight Operations')
ax.grid(True, alpha=0.3)
ax.legend()
plt.xticks(rotation=45)
plt.tight_layout()
plt.savefig(f"{visualization_dir}/01_daily_flights_timeseries.pdf", bbox_inches='tight')
plt.close()
print("  Saved: 01_daily_flights_timeseries.pdf")

# Plot 2: Distribution of daily flights
fig, ax = plt.subplots(figsize=(10, 6))
ax.hist(daily_stats['Departures'], bins=30, color='steelblue', edgecolor='black', alpha=0.7)
ax.axvline(daily_statistics['Mean_Flights_Per_Day'], color='red', linestyle='--', linewidth=2,
          label=f'Mean: {daily_statistics["Mean_Flights_Per_Day"]:.1f}')
ax.axvline(daily_statistics['Median_Flights_Per_Day'], color='green', linestyle='--', linewidth=2,
          label=f'Median: {daily_statistics["Median_Flights_Per_Day"]:.1f}')
ax.set_xlabel('Number of Flight Operations')
ax.set_ylabel('Frequency (Number of Days)')
ax.set_title('BIMTRA (RMSP-Only): Distribution of Daily Helicopter Flight Operations')
ax.legend()
ax.grid(True, alpha=0.3, axis='y')
plt.tight_layout()
plt.savefig(f"{visualization_dir}/02_daily_flights_distribution.pdf", bbox_inches='tight')
plt.close()
print("  Saved: 02_daily_flights_distribution.pdf")

# Plot 3: Top aircraft
fig, ax = plt.subplots(figsize=(12, 6))
top_aircraft = aircraft_stats.head(10)
bars = ax.barh(top_aircraft['Aircraft'], top_aircraft['Departures'], color='steelblue', edgecolor='black')
ax.set_xlabel('Number of Departures (D)')
ax.set_title('BIMTRA (RMSP-Only): Top 10 Aircraft by Departures')
ax.invert_yaxis()
for i, bar in enumerate(bars):
    width = bar.get_width()
    ax.text(width, bar.get_y() + bar.get_height()/2, f' {int(width)}', 
            ha='left', va='center', fontsize=9)
plt.tight_layout()
plt.savefig(f"{visualization_dir}/03_top_aircraft.pdf", bbox_inches='tight')
plt.close()
print("  Saved: 03_top_aircraft.pdf")

# Plot 4: Hourly operations (total)
fig, ax = plt.subplots(figsize=(12, 6))
ax.bar(hourly_stats['Hour'], hourly_stats['Total_Departures'], color='steelblue', edgecolor='black', alpha=0.7)
ax.set_xlabel('Hour of Day')
ax.set_ylabel('Total Number of Departures (D)')
ax.set_title('BIMTRA (RMSP-Only): Total Helicopter Departures by Hour')
ax.set_xticks(range(0, 24, 1))
ax.grid(True, alpha=0.3, axis='y')
plt.tight_layout()
plt.savefig(f"{visualization_dir}/04_hourly_operations.pdf", bbox_inches='tight')
plt.close()
print("  Saved: 04_hourly_operations.pdf")

# Plot 5: Equipment type distribution
fig, ax = plt.subplots(figsize=(10, 6))
bars = ax.bar(equipment_stats['Equipment'], equipment_stats['Departures'], 
              color='teal', edgecolor='black', alpha=0.7)
ax.set_ylabel('Number of Departures (D)')
ax.set_title('BIMTRA (RMSP-Only): Helicopter Fleet Composition by Departures')
ax.set_xticklabels(equipment_stats['Equipment'], rotation=45, ha='right')
for i, bar in enumerate(bars):
    height = bar.get_height()
    ax.text(bar.get_x() + bar.get_width()/2., height, f'{int(height)}',
            ha='center', va='bottom', fontsize=9)
plt.tight_layout()
plt.savefig(f"{visualization_dir}/05_equipment_distribution.pdf", bbox_inches='tight')
plt.close()
print("  Saved: 05_equipment_distribution.pdf")

# Plot 6: Top routes
fig, ax = plt.subplots(figsize=(12, 6))
top_routes = routes.head(10)
route_labels = [f"{o}-{d}" for o, d in zip(top_routes['Origin'], top_routes['Destination'])]
bars = ax.barh(route_labels, top_routes['Departures'], color='orange', edgecolor='black', alpha=0.7)
ax.set_xlabel('Number of Departures (D)')
ax.set_title('BIMTRA (RMSP-Only): Top 10 Routes by Departures')
ax.invert_yaxis()
for i, bar in enumerate(bars):
    width = bar.get_width()
    ax.text(width, bar.get_y() + bar.get_height()/2, f' {int(width)}', 
            ha='left', va='center', fontsize=9)
plt.tight_layout()
plt.savefig(f"{visualization_dir}/06_top_routes.pdf", bbox_inches='tight')
plt.close()
print("  Saved: 06_top_routes.pdf")

# Plot 7: Top heliports by total demand
fig, ax = plt.subplots(figsize=(12, 8))
top_heliports = heliport_stats.head(15)
x = range(len(top_heliports))
width = 0.35

bars1 = ax.barh([i - width/2 for i in x], top_heliports['Outbound_Flights'], width, 
                label='Outbound', color='steelblue', edgecolor='black', alpha=0.8)
bars2 = ax.barh([i + width/2 for i in x], top_heliports['Inbound_Flights'], width, 
                label='Inbound', color='coral', edgecolor='black', alpha=0.8)

ax.set_yticks(x)
ax.set_yticklabels(top_heliports['Heliport'])
ax.set_xlabel('Number of Flight Operations')
ax.set_title('BIMTRA (RMSP-Only): Top 15 Heliports by Total Demand (Outbound + Inbound)')
ax.legend()
ax.invert_yaxis()
ax.grid(True, alpha=0.3, axis='x')

# Add value labels
for bars in [bars1, bars2]:
    for bar in bars:
        width_val = bar.get_width()
        if width_val > 0:
            ax.text(width_val, bar.get_y() + bar.get_height()/2, f' {int(width_val)}', 
                    ha='left', va='center', fontsize=8)

plt.tight_layout()
plt.savefig(f"{visualization_dir}/07_top_heliports_demand.pdf", bbox_inches='tight')
plt.close()
print("  Saved: 07_top_heliports_demand.pdf")

# Plot 8: Heliports demand breakdown - Top 10 with stacked bar
fig, ax = plt.subplots(figsize=(12, 6))
top_10_heliports = heliport_stats.head(10)
x_pos = range(len(top_10_heliports))

bars1 = ax.bar(x_pos, top_10_heliports['Outbound_Flights'], label='Outbound', 
               color='steelblue', edgecolor='black', alpha=0.8)
bars2 = ax.bar(x_pos, top_10_heliports['Inbound_Flights'], 
               bottom=top_10_heliports['Outbound_Flights'], 
               label='Inbound', color='coral', edgecolor='black', alpha=0.8)

ax.set_ylabel('Number of Flight Operations')
ax.set_title('BIMTRA (RMSP-Only): Top 10 Heliports - Outbound vs Inbound Breakdown')
ax.set_xticks(x_pos)
ax.set_xticklabels(top_10_heliports['Heliport'], rotation=45, ha='right')
ax.legend()
ax.grid(True, alpha=0.3, axis='y')

# Add total labels on top of bars
for i, (idx, row) in enumerate(top_10_heliports.iterrows()):
    total = row['Total_Flights']
    ax.text(i, total, f'{int(total)}', ha='center', va='bottom', fontsize=9, fontweight='bold')

plt.tight_layout()
plt.savefig(f"{visualization_dir}/08_heliports_stacked_breakdown.pdf", bbox_inches='tight')
plt.close()
print("  Saved: 08_heliports_stacked_breakdown.pdf")

# Plot 9: Box plot of daily operations
fig, ax = plt.subplots(figsize=(10, 6))
box_data = [daily_stats['Departures']]
bp = ax.boxplot(box_data, labels=['Daily Departures (RMSP-only)'], patch_artist=True)
bp['boxes'][0].set_facecolor('lightblue')
ax.set_ylabel('Number of Departures (D)')
ax.set_title('BIMTRA (RMSP-Only): Daily Departures Statistical Summary')
ax.grid(True, alpha=0.3, axis='y')

# Add statistics text
stats_text = f"""
Min: {daily_statistics['Min_Flights_Per_Day']:.0f}
Q1: {daily_stats['Departures'].quantile(0.25):.0f}
Median: {daily_statistics['Median_Flights_Per_Day']:.0f}
Q3: {daily_stats['Departures'].quantile(0.75):.0f}
Max: {daily_statistics['Max_Flights_Per_Day']:.0f}
Mean: {daily_statistics['Mean_Flights_Per_Day']:.2f}
Std: {daily_statistics['Std_Dev_Flights']:.2f}
"""
ax.text(1.15, daily_stats['Departures'].mean(), stats_text, 
        fontsize=9, verticalalignment='center', family='monospace',
        bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.5))

plt.tight_layout()
plt.savefig(f"{visualization_dir}/09_operations_boxplot.pdf", bbox_inches='tight')
plt.close()
print("  Saved: 09_operations_boxplot.pdf")

print("\n")
print("========== SUCCESS (RMSP-ONLY ANALYSIS) ==========")
print(f"Output files saved to: {output_dir}")
print(f"Visualizations saved to: {visualization_dir}\n")

# %%
