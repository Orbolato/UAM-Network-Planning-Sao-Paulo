import pandas as pd
import re

print("Carregando arquivo Helipontos.csv da ANAC...")

# Carregar arquivo
df = pd.read_csv("data/raw/anac/Helipontos.csv", 
                 sep=";", 
                 encoding="latin1",
                 skiprows=1)  # Pular linha de data

print(f"Total de helipontos no arquivo ANAC: {len(df)}\n")

# Municípios da RMSP (39 municípios oficiais)
rmsp_municipios = [
    "SÃO PAULO", "GUARULHOS", "SÃO BERNARDO DO CAMPO", "SANTO ANDRÉ", 
    "OSASCO", "SÃO CAETANO DO SUL", "MAUÁ", "DIADEMA", "CARAPICUÍBA",
    "ITAQUAQUECETUBA", "SUZANO", "TABOÃO DA SERRA", "BARUERI", "EMBU DAS ARTES",
    "COTIA", "FERRAZ DE VASCONCELOS", "FRANCISCO MORATO", "ITAPECERICA DA SERRA",
    "ITAPEVI", "JANDIRA", "MAIRIPORÃ", "MOGI DAS CRUZES", "POÁ", "RIBEIRÃO PIRES",
    "RIO GRANDE DA SERRA", "SANTANA DE PARNAÍBA", "ARUJÁ", "BIRITIBA-MIRIM",
    "CAIEIRAS", "CAJAMAR", "EMBU-GUAÇU", "GUARAREMA", "JUQUITIBA", "SALESÓPOLIS",
    "SANTA ISABEL", "SÃO LOURENÇO DA SERRA", "VARGEM GRANDE PAULISTA"
]

# Função para converter coordenadas DMS para decimal
def dms_para_decimal(coord_str, tipo):
    """Converte coordenadas DMS (graus, minutos, segundos) para decimal"""
    if pd.isna(coord_str):
        return None
    
    # Extrair números
    numeros = re.findall(r'\d+[,.]?\d*', str(coord_str))
    if len(numeros) < 2:
        return None
    
    # Converter para float
    numeros = [float(n.replace(',', '.')) for n in numeros]
    
    # Calcular decimal
    graus = numeros[0]
    minutos = numeros[1] if len(numeros) >= 2 else 0
    segundos = numeros[2] if len(numeros) >= 3 else 0
    
    decimal = graus + minutos/60 + segundos/3600
    
    # Aplicar sinal negativo para Sul e Oeste
    if tipo == "lat" and "S" in str(coord_str):
        decimal = -decimal
    elif tipo == "lon" and "W" in str(coord_str):
        decimal = -decimal
    
    return decimal

# Encontrar nomes corretos das colunas
col_municipio = [c for c in df.columns if 'Munic' in c][0]
col_codigo = [c for c in df.columns if 'OACI' in c][0]
col_nome = [c for c in df.columns if c == 'Nome'][0]
col_tipo = [c for c in df.columns if c == 'Tipo'][0]
col_latitude = [c for c in df.columns if 'Latitude' in c][0]
col_longitude = [c for c in df.columns if 'Longitude' in c][0]
col_op_diurna = [c for c in df.columns if 'Diurna' in c][0]
col_op_noturna = [c for c in df.columns if 'Noturna' in c][0]

print(f"Colunas identificadas:")
print(f"  Código: {col_codigo}")
print(f"  Nome: {col_nome}")
print(f"  Tipo: {col_tipo}")
print(f"  Município: {col_municipio}")
print(f"  Latitude: {col_latitude}")
print(f"  Longitude: {col_longitude}\n")

# Filtrar RMSP
df['municipio_norm'] = df[col_municipio].str.upper().str.strip()
df_rmsp = df[df['municipio_norm'].isin(rmsp_municipios)].copy()

print(f"Helipontos encontrados na RMSP: {len(df_rmsp)}\n")

# Converter coordenadas
print("Convertendo coordenadas...")
df_rmsp['lat'] = df_rmsp[col_latitude].apply(lambda x: dms_para_decimal(x, 'lat'))
df_rmsp['lon'] = df_rmsp[col_longitude].apply(lambda x: dms_para_decimal(x, 'lon'))

# Preparar operação
def determinar_operacao(row):
    diurna = row[col_op_diurna]
    noturna = row[col_op_noturna]
    
    if diurna == "VFR" and noturna == "VFR":
        return "Diurna/Noturna"
    elif diurna == "VFR":
        return "Diurna"
    elif "IFR" in str(diurna):
        return "Diurna/Noturna"
    else:
        return "Diurna"

df_rmsp['operacao'] = df_rmsp.apply(determinar_operacao, axis=1)

# Selecionar colunas finais
resultado = df_rmsp[[col_codigo, col_nome, col_tipo, 'lat', 'lon', 'operacao', 'municipio_norm']].copy()
resultado.columns = ['codigo', 'name', 'tipo', 'lat', 'lon', 'operacao', 'municipio']

# Remover linhas sem coordenadas
resultado = resultado.dropna(subset=['lat', 'lon'])

# Ordenar
resultado = resultado.sort_values(['municipio', 'name'])

print(f"Helipontos com coordenadas válidas: {len(resultado)}\n")

# Resumo por município
print("=== RESUMO POR MUNICÍPIO ===")
resumo_mun = resultado.groupby('municipio').size().sort_values(ascending=False)
print(resumo_mun.to_string())

# Resumo por tipo
print("\n=== RESUMO POR TIPO ===")
resumo_tipo = resultado.groupby('tipo').size().sort_values(ascending=False)
print(resumo_tipo.to_string())

# Salvar arquivo
print("\n=== SALVANDO ARQUIVO ===")
resultado.to_csv("data/interim/helipontos_rmsp_anac.csv", index=False, encoding='utf-8')
print(f"Arquivo salvo: data/interim/helipontos_rmsp_anac.csv")
print(f"Total de helipontos salvos: {len(resultado)}\n")

# Mostrar primeiros registros
print("=== PRIMEIROS 10 HELIPONTOS ===")
print(resultado.head(10).to_string(index=False))

print("\n✓ Processamento concluído!")
