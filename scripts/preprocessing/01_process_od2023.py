"""
Processar dados da Pesquisa OD 2023 - RMSP
Extrai e converte dados de população, viagens, renda e matriz OD
"""

import pandas as pd
import numpy as np
import os

print("=" * 80)
print("PROCESSAMENTO DE DADOS OD 2023 - RMSP")
print("=" * 80)

# Diretórios
base_dir = "data/raw/od2023"
output_dir = "data/interim"
excel_file = os.path.join(base_dir, "Tabelas_Site_OD2023_REV_190225.xlsx")

# Criar diretório de saída se não existir
os.makedirs(output_dir, exist_ok=True)

# ========== TABELA 1: POPULAÇÃO, EMPREGOS, DOMICÍLIOS POR ZONA ==========
print("\n1. Processando Tabela 1 - População e características das zonas...")
try:
    # Ler Tab1 - header está na linha 8 (skiprows=7)
    df_tab1 = pd.read_excel(excel_file, sheet_name='Tab1', skiprows=7)
    
    # Limpar espaços nos nomes das colunas
    df_tab1.columns = [col.strip() if isinstance(col, str) else col for col in df_tab1.columns]
    
    # Limpar dados vazios
    df_tab1 = df_tab1.dropna(how='all')
    
    # Converter zona para inteiro e filtrar linhas válidas
    df_tab1['zona'] = pd.to_numeric(df_tab1['Zona'], errors='coerce')
    df_tab1 = df_tab1[df_tab1['zona'].notna()]
    df_tab1['zona'] = df_tab1['zona'].astype(int)
    
    # Mapear colunas para nomes padronizados
    rename_map = {
        'Nome': 'nome_zona',
        'Domicílios': 'domicilios',
        'Famílias': 'familias',
        'População': 'populacao',
        'Escolares': 'matriculas',
        'Empregos': 'empregos',
        'Particulares': 'automoveis',
        'Produzidas': 'viagens_produzidas',
        'Atraidas': 'viagens_atraidas',
        'Área (ha)': 'area_ha'
    }
    df_tab1 = df_tab1.rename(columns=rename_map)
    
    # Converter colunas numéricas
    for col in ['populacao', 'domicilios', 'familias', 'empregos', 'matriculas', 
                'automoveis', 'viagens_produzidas', 'viagens_atraidas', 'area_ha']:
        if col in df_tab1.columns:
            df_tab1[col] = pd.to_numeric(df_tab1[col], errors='coerce').fillna(0)
    
    print(f"   Total de zonas: {len(df_tab1)}")
    print(f"   População total: {df_tab1['populacao'].sum():,.0f}")
    print(f"   Viagens produzidas: {df_tab1['viagens_produzidas'].sum():,.0f}")
    print(f"   Viagens atraídas: {df_tab1['viagens_atraidas'].sum():,.0f}")
    
    # Preparar dataframe de saída
    df_base = df_tab1.copy()
    
    print("   ✓ Tabela 1 processada com sucesso")

except Exception as e:
    print(f"   ✗ Erro ao processar Tabela 1: {e}")
    import traceback
    traceback.print_exc()
    df_base = None

# ========== TABELA 6: RENDA POR ZONA ==========
print("\n2. Processando Tabela 6 - Renda por zona...")
try:
    df_tab6 = pd.read_excel(excel_file, sheet_name='Tab6', skiprows=7)
    
    # Limpar dados vazios
    df_tab6 = df_tab6.dropna(how='all')
    
    # Limpar espaços nos nomes das colunas
    df_tab6.columns = [col.strip() if isinstance(col, str) else col for col in df_tab6.columns]
    
    # Converter zona para inteiro e filtrar linhas válidas
    df_tab6['zona'] = pd.to_numeric(df_tab6['Residência'], errors='coerce')
    df_tab6 = df_tab6[df_tab6['zona'].notna()]
    df_tab6['zona'] = df_tab6['zona'].astype(int)
    
    # Renomear colunas de renda
    # Colunas: Residência, Total, Familiar, Per Capita, Familiar.1 (mediana)
    df_tab6 = df_tab6.rename(columns={
        'Total': 'renda_total',
        'Familiar': 'renda_familiar_media',
        'Per Capita': 'renda_per_capita',
        'Familiar.1': 'renda_familiar_mediana'
    })
    
    # Converter colunas numéricas
    for col in ['renda_total', 'renda_familiar_media', 'renda_per_capita', 'renda_familiar_mediana']:
        if col in df_tab6.columns:
            df_tab6[col] = pd.to_numeric(df_tab6[col], errors='coerce').fillna(0)
    
    # Calcular renda em salários mínimos (SM 2023: R$ 1.320)
    salario_minimo = 1320
    df_tab6['renda_sm'] = df_tab6['renda_familiar_media'] / salario_minimo
    
    print(f"   Total de zonas: {len(df_tab6)}")
    print(f"   Renda familiar média: R$ {df_tab6['renda_familiar_media'].mean():,.2f}")
    print(f"   Renda per capita média: R$ {df_tab6['renda_per_capita'].mean():,.2f}")
    print(f"   Renda em SM: {df_tab6['renda_sm'].mean():.2f} SM")
    
    # Salvar CSV de renda
    output_renda = os.path.join(output_dir, "renda_per_capita_rmsp.csv")
    df_renda = df_tab6[['zona', 'renda_total', 'renda_familiar_media', 
                         'renda_per_capita', 'renda_familiar_mediana', 'renda_sm']].copy()
    df_renda.to_csv(output_renda, index=False, encoding='utf-8-sig')
    print(f"   ✓ Renda salva em: {output_renda}")
    
except Exception as e:
    print(f"   ✗ Erro ao processar Tabela 6: {e}")
    import traceback
    traceback.print_exc()

# ========== TABELA 25: MATRIZ OD ==========
print("\n3. Processando Tabela 25 - Matriz Origem-Destino...")
try:
    # Ler matriz sem header
    df_matriz = pd.read_excel(excel_file, sheet_name='Tab25', skiprows=6, header=None)
    df_matriz = df_matriz.dropna(how='all')
    
    # Row 1 (after label row 0) has destination zone numbers
    dest_zones_row = df_matriz.iloc[1, 1:].tolist()
    
    # Data starts from row 2
    df_matriz = df_matriz.iloc[2:].reset_index(drop=True)
    
    # Build destination zone list (skip non-numeric like 'Total')
    dest_zones = []
    for z in dest_zones_row:
        if pd.notna(z) and isinstance(z, (int, float)):
            dest_zones.append(int(z))
        else:
            dest_zones.append(None)
    
    # Set column names
    df_matriz.columns = ['origem'] + dest_zones[:len(df_matriz.columns)-1]
    
    # Convert origin to numeric
    df_matriz['origem'] = pd.to_numeric(df_matriz['origem'], errors='coerce')
    df_matriz = df_matriz[df_matriz['origem'].notna()]
    df_matriz['origem'] = df_matriz['origem'].astype(int)
    
    print(f"   Dimensão da matriz: {len(df_matriz)} origens × {len([z for z in dest_zones if z is not None])} destinos")
    
    # Converter para formato longo
    matriz_longa = []
    
    for idx, row in df_matriz.iterrows():
        origem = int(row['origem'])
        for col in df_matriz.columns[1:]:
            if col is not None and isinstance(col, int):
                viagens = pd.to_numeric(row[col], errors='coerce')
                if pd.notna(viagens) and viagens > 0:
                    matriz_longa.append({
                        'origem': origem,
                        'destino': col,
                        'viagens': viagens
                    })
    
    df_od = pd.DataFrame(matriz_longa)
    
    if len(df_od) > 0:
        print(f"   Total de pares OD com viagens: {len(df_od):,}")
        print(f"   Total de viagens: {df_od['viagens'].sum():,.0f}")
        
        # Salvar CSV
        output_od = os.path.join(output_dir, "matriz_od_tabela_25.csv")
        df_od.to_csv(output_od, index=False, encoding='utf-8-sig')
        print(f"   ✓ Matriz OD salva em: {output_od}")
    else:
        print("   ⚠ Nenhuma viagem encontrada na matriz")
    
except Exception as e:
    print(f"   ✗ Erro ao processar Tabela 25: {e}")
    import traceback
    traceback.print_exc()

# ========== SALVAR DADOS PRINCIPAIS ==========
if df_base is not None:
    print("\n4. Salvando dados consolidados...")
    
    # Selecionar colunas principais
    colunas_saida = ['zona']
    for col in ['nome_zona', 'populacao', 'domicilios', 'familias', 'empregos', 
                'matriculas', 'automoveis', 'viagens_produzidas', 'viagens_atraidas', 
                'area_ha', 'area_km2']:
        if col in df_base.columns:
            colunas_saida.append(col)
    
    df_saida = df_base[colunas_saida].copy()
    
    # Salvar CSV
    output_zonas = os.path.join(output_dir, "dados_zonas_rmsp.csv")
    df_saida.to_csv(output_zonas, index=False, encoding='utf-8-sig')
    print(f"   ✓ Dados das zonas salvos em: {output_zonas}")
    print(f"   Total de zonas: {len(df_saida)}")
    
    # Estatísticas finais
    print("\n" + "=" * 80)
    print("RESUMO FINAL - OD 2023")
    print("=" * 80)
    print(f"Total de zonas RMSP: {len(df_saida)}")
    if 'populacao' in df_saida.columns:
        print(f"População total: {df_saida['populacao'].sum():,.0f} habitantes")
    if 'domicilios' in df_saida.columns:
        print(f"Total de domicílios: {df_saida['domicilios'].sum():,.0f}")
    if 'empregos' in df_saida.columns:
        print(f"Total de empregos: {df_saida['empregos'].sum():,.0f}")
    if 'viagens_produzidas' in df_saida.columns:
        print(f"Viagens produzidas: {df_saida['viagens_produzidas'].sum():,.0f}")
    if 'viagens_atraidas' in df_saida.columns:
        print(f"Viagens atraídas: {df_saida['viagens_atraidas'].sum():,.0f}")
    print("=" * 80)

print("\n✓ Processamento concluído!")
