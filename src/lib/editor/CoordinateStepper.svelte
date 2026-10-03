<script>
    let {
        axis = 'x',
        value = $bindable(''),
        disabled = false,
        invalid = false,
        step = 1,
        onValueChange = () => {}
    } = $props();

    let decrementSymbol = $derived(axis === 'y' ? '↓' : '←');
    let incrementSymbol = $derived(axis === 'y' ? '↑' : '→');

    function nudge(direction) {
        const amount = Number(step) || 1;
        value = String((Number(value) || 0) + direction * amount);
        onValueChange(value);
    }

    function handleInput() {
        onValueChange(value);
    }
</script>

<div class:invalid class="coordinate-stepper">
    <button
        type="button"
        aria-label={`${axis.toUpperCase()} - ${step}`}
        onclick={() => nudge(-1)}
        {disabled}
    >{decrementSymbol}</button>

    <input
        type="number"
        {step}
        bind:value
        oninput={handleInput}
        {disabled}
        inputmode="numeric"
    />

    <button
        type="button"
        aria-label={`${axis.toUpperCase()} + ${step}`}
        onclick={() => nudge(1)}
        {disabled}
    >{incrementSymbol}</button>
</div>

<style>
    .coordinate-stepper {
        display:grid;
        grid-template-columns:38px minmax(0,1fr) 38px;
        align-items:stretch;
        min-width:0;
        border:1px solid #34343e;
        border-radius:8px;
        background:#0f0f13;
        overflow:hidden;
        transition:border-color .15s ease, box-shadow .15s ease;
    }

    .coordinate-stepper:focus-within {
        border-color:#c8a355;
        box-shadow:0 0 0 2px rgba(200,163,85,.11);
    }

    .coordinate-stepper.invalid {
        border-color:#c85f67;
        box-shadow:0 0 0 2px rgba(200,95,103,.12);
    }

    input {
        min-width:0;
        width:100%;
        box-sizing:border-box;
        border:0;
        border-radius:0;
        outline:0;
        background:#0f0f13;
        color:#f2f2f4;
        padding:9px 10px;
        text-align:center;
        font:inherit;
        appearance:textfield;
        -moz-appearance:textfield;
    }

    input::-webkit-outer-spin-button,
    input::-webkit-inner-spin-button {
        -webkit-appearance:none;
        margin:0;
    }

    button {
        border:0;
        background:#17171c;
        color:#d8b86f;
        font:inherit;
        font-size:1rem;
        font-weight:800;
        cursor:pointer;
    }

    button:first-child { border-right:1px solid #34343e; }
    button:last-child { border-left:1px solid #34343e; }

    button:hover:not(:disabled) { background:#211d14; }
    button:disabled,input:disabled { opacity:.5; cursor:not-allowed; }
</style>
