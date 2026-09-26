
/* ==========================================
   CATEGORIAS — ELDEN RING
   ==========================================

   Aqui ficam as categorias específicas
   deste jogo.

   Cada categoria controla:
   - tradução
   - ícone
   - cor do pino
   - grupo do filtro
*/


export const categories = {

    site_of_grace: {
        id: 'site_of_grace',
        labelKey: 'sites_of_grace',
        group: 'locations',

        icon: '/icons/site-of-grace.png',

        color: '#23233a',

        markerWidth: 30,
        markerHeight: 39,

        symbolSize: 22
    },


    dungeon: {
        id: 'dungeon',
        labelKey: 'dungeons_caverns',
        group: 'locations',

        icon: null,

        color: '#7b6b91'
    },


    boss: {
        id: 'boss',
        labelKey: 'bosses',
        group: 'locations',

        icon: null,

        color: '#8f4f4f'
    },


    weapon_equipment: {
        id: 'weapon_equipment',
        labelKey: 'weapons_equipment',
        group: 'collectibles',

        icon: null,

        color: '#557a8f'
    },


    stonesword_key: {
        id: 'stonesword_key',
        labelKey: 'stonesword_keys',
        group: 'collectibles',

        icon: null,

        color: '#777777'
    },


    talisman: {
        id: 'talisman',
        labelKey: 'talismans',
        group: 'collectibles',

        icon: null,

        color: '#8b7545'
    }
};


/* Grupos exibidos na sidebar, pela ordem definida para este jogo. */

export const categoryGroups = [
    { id: 'locations', labelKey: 'locations' },
    { id: 'collectibles', labelKey: 'collectibles' }
];


/* ==========================================
   ESTADO INICIAL DOS FILTROS
   ========================================== */

export const defaultCategoryVisibility = {

    site_of_grace: true,

    dungeon: true,

    boss: true,

    weapon_equipment: true,

    stonesword_key: true,

    talisman: true
};
