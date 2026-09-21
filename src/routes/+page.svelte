<script>
  import { onMount } from 'svelte';
  import 'leaflet/dist/leaflet.css';

  let map;

  // Dimensões da tua imagem do Elden Ring (8000x8000)
  const MAP_HEIGHT = 8000; 
  const MAP_WIDTH = 8000;

  onMount(async () => {
    const L = await import('leaflet');

    // Configuração do Leaflet
    map = L.map('map', {
      crs: L.CRS.Simple,
      minZoom: -4,
      maxZoom: 3,
      zoomSnap: 0.5,
      attributionControl: false // Remove o texto "Leaflet"
    });

    const bounds = [[0, 0], [MAP_HEIGHT, MAP_WIDTH]];
    const imageUrl = '/mapa-elden-ring.jpg'; 
    L.imageOverlay(imageUrl, bounds).addTo(map);

    map.fitBounds(bounds);
  });
</script>

<div class="app-container">
  <!-- Header -->
  <header class="header">
    <div class="logo-container">
      <img src="/logo.png" alt="DeepMap Logo" class="logo-img" />
      <span class="divider">|</span>
      <span class="gold-text">ELDEN RING MAP</span>
    </div>
    <div class="user-actions">
      <button class="btn-gold">Checklist (0%)</button>
      <button class="btn-login">Login</button>
    </div>
  </header>

  <div class="main-content">
    <!-- Painel Lateral -->
    <aside class="sidebar">
      <h2>Filtros</h2>
      <div class="filter-group">
        <label><input type="checkbox" checked /> Sites of Grace</label>
        <label><input type="checkbox" checked /> Bosses</label>
        <label><input type="checkbox" checked /> Weapons / Armor</label>
        <label><input type="checkbox" checked /> Dungeons & Caves</label>
      </div>
    </aside>

    <!-- Contentor do Mapa com a Marca de Água -->
    <div id="map">
      <img src="/logo.png" alt="DeepMap Watermark" class="map-watermark-img" />
    </div>
  </div>
</div>

<style>
  :global(body) {
    margin: 0;
    padding: 0;
    background-color: #0f0f11;
    color: #e0e0e0;
    font-family: system-ui, -apple-system, sans-serif;
  }

  .app-container {
    display: flex;
    flex-direction: column;
    height: 100vh;
  }

  .header {
    height: 60px;
    background-color: #16161a;
    border-bottom: 2px solid #c8a355;
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0 20px;
  }

  .logo-container {
    display: flex;
    align-items: center;
    gap: 14px;
  }

  .logo-img {
    height: 36px;
    width: auto;
    object-fit: contain;
  }

  .divider {
    color: #3a3a42;
    font-size: 1.2rem;
  }

  .gold-text {
    color: #c8a355;
    font-weight: bold;
    letter-spacing: 2px;
    font-size: 1.1rem;
  }

  .main-content {
    display: flex;
    flex: 1;
    height: calc(100vh - 60px);
  }

  .sidebar {
    width: 280px;
    background-color: #16161a;
    border-right: 1px solid #2a2a30;
    padding: 20px;
    box-sizing: border-box;
  }

  /* ESTILOS DO MAPA E DA MARCA DE ÁGUA */
  #map {
    position: relative; /* OBRIGATÓRIO: Mantém o logo dentro do mapa */
    flex: 1;
    height: 100%;
    background-color: #0b0b0d;
  }

  .map-watermark-img {
    position: absolute;   /* OBRIGATÓRIO: Fixa o logo sobre a imagem do mapa */
    bottom: 15px;         /* Distância do fundo */
    right: 15px;          /* Distância da direita */
    z-index: 1000;        /* Fica por cima da imagem do mapa */
    height: 28px;         /* Tamanho do logo no canto */
    width: auto;
    opacity: 0.35;        /* Transparência discreta */
    pointer-events: none; /* Permite arrastar o mapa por trás do logo */
  }

  .filter-group label {
    display: block;
    margin: 12px 0;
    cursor: pointer;
    font-size: 14px;
  }

  .btn-gold {
    background: #c8a355;
    color: #000;
    border: none;
    padding: 8px 16px;
    font-weight: bold;
    cursor: pointer;
    border-radius: 4px;
  }

  .btn-login {
    background: transparent;
    color: #c8a355;
    border: 1px solid #c8a355;
    padding: 8px 16px;
    margin-left: 10px;
    cursor: pointer;
    border-radius: 4px;
  }
</style>