`timescale 1ns/1ps
//==============================================================================
// Testbench auto-verificável - uart_tx (Trabalho 5 - Transmissor UART)
//------------------------------------------------------------------------------
// O que é verificado (sem precisar olhar a forma de onda):
//  * Quadro 8N1: start bit = 0, 8 bits de dados (LSB primeiro), stop bit = 1
//  * Taxa de cada seleção: 00=9600, 01=19200, 10=28800, 11=57600 bps
//      - cada bit tem que ficar estável de 10% a 90% do seu intervalo
//      - o baud medido nas bordas do quadro tem que estar a <2% do nominal
//  * Scoreboard: todo byte aceito sai uma única vez, na ordem, e nada além
//  * Linha em repouso = 1 (após o reset, sem dados e entre quadros)
//  * Escrita com buffer_full = 1 é descartada; com buffer_full = 0 é aceita
//  * Troca de taxa no meio de um quadro não corrompe o quadro em andamento
//  * Reset (assíncrono) no meio de uma transmissão: linha vai a 1 na hora,
//    os bytes pendentes são descartados e o circuito volta a funcionar
//  * Nenhum X/Z nas saídas depois do reset
//
// Só usa as portas do DUT -> serve para o RTL (sim.do) e a netlist
// (sim_synth.do). Rode com "run -all": o testbench chama $finish sozinho
// e imprime TESTE PASSOU / TESTE FALHOU no final.
// Semente do teste aleatório: vsim ... +SEED=123 (padrão 1).
//==============================================================================
module tb_top;

  //--------------------------------------------------------------------------
  // Parâmetros do teste
  //--------------------------------------------------------------------------
  localparam real CLK_PERIOD  = 10.0;   // ns -> 100 MHz
  localparam real JANELA      = 0.10;   // bit estável entre 10% e 90%
  localparam real TOL_BAUD    = 0.02;   // erro máximo do baud medido
  localparam int  N_GRUPOS    = 6;      // grupos do teste aleatório
  localparam real WATCHDOG_NS = 60.0e6; // 60 ms simulados no máximo

  //--------------------------------------------------------------------------
  // Sinais do DUT
  //--------------------------------------------------------------------------
  logic       clock_in         = 1'b0;
  logic       reset_in         = 1'b1;
  logic [7:0] data_p_in        = 8'h00;
  logic       data_p_en_in     = 1'b0;
  logic [1:0] uart_rate_tx_sel = 2'b00;
  logic       buffer_full;
  logic       uart_data_tx;

  uart_tx dut (
    .clock_in         (clock_in),
    .reset_in         (reset_in),
    .data_p_in        (data_p_in),
    .data_p_en_in     (data_p_en_in),
    .uart_rate_tx_sel (uart_rate_tx_sel),
    .buffer_full      (buffer_full),
    .uart_data_tx     (uart_data_tx)
  );

  // Clock de 100 MHz: subida em 5, 15, 25 ns...; descida em 10, 20, 30 ns...
  always #(CLK_PERIOD / 2.0) clock_in = ~clock_in;

  //--------------------------------------------------------------------------
  // Funções auxiliares
  //--------------------------------------------------------------------------
  function automatic int baud_de(input logic [1:0] sel);
    case (sel)
      2'b00:   return 9600;
      2'b01:   return 19200;
      2'b10:   return 28800;
      default: return 57600;
    endcase
  endfunction

  // Período de bit nominal em ns
  function automatic real periodo_bit(input logic [1:0] sel);
    return 1.0e9 / baud_de(sel);
  endfunction

  function automatic string nome_bit(input int k);
    if (k == 0) return "start";
    if (k == 9) return "stop";
    return $sformatf("d%0d", k - 1);
  endfunction

  function automatic string ascii(input logic [7:0] b);
    if (b >= 8'h20 && b <= 8'h7E) return $sformatf("'%c'", b);
    return "   ";
  endfunction

  //--------------------------------------------------------------------------
  // Scoreboard e contadores
  //--------------------------------------------------------------------------
  // Bytes aceitos pelo DUT que ainda não chegaram.
  // Cada item = {taxa esperada (2 bits), dado (8 bits)}
  logic [9:0] esperado[$];

  int n_erros       = 0;
  int n_quadros     = 0;  // quadros vistos pelo monitor
  int n_quadros_ok  = 0;
  int n_aceitos     = 0;  // escritas aceitas (buffer_full = 0)
  int n_descartados = 0;  // escritas ignoradas (buffer_full = 1)
  int n_limpos      = 0;  // bytes pendentes apagados por reset
  int n_abortados   = 0;  // quadros interrompidos por reset
  bit monitor_ocupado = 1'b0;
  bit checa_x         = 1'b0;
  int unsigned semente;

  task automatic erro(input string msg);
    n_erros++;
    $error("[%t] %s", $realtime, msg);
  endtask

  // Saídas nunca podem ter X/Z depois do reset
  always @(posedge uart_data_tx or negedge uart_data_tx or
           posedge buffer_full  or negedge buffer_full)
    if (checa_x && ($isunknown(uart_data_tx) || $isunknown(buffer_full)))
      erro($sformatf("saída com X/Z: uart_data_tx=%b buffer_full=%b",
                     uart_data_tx, buffer_full));

  //--------------------------------------------------------------------------
  // Monitor / receptor UART de referência
  //--------------------------------------------------------------------------
  // A cada borda de descida da linha (start bit), retira do scoreboard o
  // próximo byte esperado e usa a taxa dele para amostrar o quadro.
  // Para cada bit k (0=start, 1..8=dados, 9=stop):
  //   - amostra no meio do bit;
  //   - verifica que não houve transição entre 10% e 90% do bit.
  // O baud real é medido pela última transição do quadro (sempre existe uma
  // subida, porque o start é 0 e o stop é 1).
  realtime ultima_borda = 0.0;  // instante da última transição da linha
  int      epoca_reset  = 0;    // muda a cada reset -> aborta o quadro

  always @(posedge uart_data_tx or negedge uart_data_tx)
    ultima_borda = $realtime;
  always @(posedge reset_in)
    epoca_reset++;

  task automatic espera_ate(input realtime t);
    if (t > $realtime) #(t - $realtime);
  endtask

  // Recebe e confere um quadro. Chamada logo após a descida do start bit.
  task automatic recebe_quadro();
    logic [1:0] exp_sel;
    logic [7:0] exp_dado;
    realtime    t0, T;
    logic [9:0] bits;
    logic [7:0] rx;
    bit         inesperado, abortado, instavel, ok;
    string      ruins, msg;
    int         epoca, k, j, baud;
    real        baud_medido;

    t0              = $realtime;
    epoca           = epoca_reset;
    monitor_ocupado = 1'b1;
    n_quadros++;
    inesperado = (esperado.size() == 0);
    if (inesperado) begin
      exp_sel  = uart_rate_tx_sel;     // só para tentar decodificar
      exp_dado = 8'h00;
    end
    else begin
      {exp_sel, exp_dado} = esperado.pop_front();
    end
    T    = periodo_bit(exp_sel);
    baud = baud_de(exp_sel);

    abortado = 1'b0;
    instavel = 1'b0;
    ruins    = "";
    bits     = 'x;
    for (k = 0; k < 10 && !abortado; k++) begin
      espera_ate(t0 + (k + 0.5) * T);            // meio do bit
      bits[k] = uart_data_tx;
      espera_ate(t0 + (k + 1.0 - JANELA) * T);   // fim da janela
      if (epoca != epoca_reset)
        abortado = 1'b1;                         // houve reset
      else if (ultima_borda > t0 + (k + JANELA) * T) begin
        instavel = 1'b1;                         // transição fora de hora
        ruins    = {ruins, " ", nome_bit(k)};
      end
    end
    monitor_ocupado = 1'b0;

    if (abortado) begin
      n_abortados++;
      $display("[%t] RX: quadro interrompido pelo reset", $realtime);
    end
    else begin
      // baud medido: a última transição cai na fronteira do bit j
      j = $rtoi((ultima_borda - t0) / T + 0.5);
      if (j >= 1) baud_medido = 1.0e9 * j / (ultima_borda - t0);
      else        baud_medido = 0.0;

      rx = bits[8:1];
      ok = !inesperado && !instavel
           && (bits[0] === 1'b0) && (bits[9] === 1'b1)
           && (rx === exp_dado)
           && (baud_medido >= baud * (1.0 - TOL_BAUD))
           && (baud_medido <= baud * (1.0 + TOL_BAUD));

      if (ok) begin
        n_quadros_ok++;
        $display("[%t] RX OK  #%0d  0x%h %s @ %0d bps (medido %0.1f bps)",
                 $realtime, n_quadros, rx, ascii(rx), baud, baud_medido);
      end
      else begin
        if (inesperado)
          msg = "quadro INESPERADO (nenhum byte pendente)";
        else
          msg = $sformatf("esperado 0x%h %s @ %0d bps",
                          exp_dado, ascii(exp_dado), baud);
        msg = $sformatf("%s | recebido 0x%h start=%b stop=%b",
                        msg, rx, bits[0], bits[9]);
        msg = $sformatf("%s | baud medido %0.1f", msg, baud_medido);
        if (instavel)
          msg = {msg, " | bits fora do tempo:", ruins};
        erro($sformatf("RX quadro #%0d: %s", n_quadros, msg));
      end
    end
  endtask

  initial begin : monitor_rx
    forever begin
      wait (reset_in === 1'b0);
      @(negedge uart_data_tx);
      if (reset_in === 1'b0)
        recebe_quadro();
    end
  end

  //--------------------------------------------------------------------------
  // Driver da interface paralela
  //--------------------------------------------------------------------------
  // Todas as tarefas trabalham na borda de DESCIDA: as entradas ficam estáveis
  // meio período antes da borda de subida, onde o DUT amostra. buffer_full
  // também é lido aqui (já estável) para saber se a escrita será aceita.
  task automatic ciclo(input logic       en,
                       input logic [7:0] dado,
                       input logic [1:0] sel_esperado);
    data_p_en_in = en;
    data_p_in    = dado;
    if (en) begin
      if (buffer_full === 1'b0) begin
        esperado.push_back({sel_esperado, dado});
        n_aceitos++;
      end
      else begin
        n_descartados++;
      end
    end
    @(negedge clock_in);
  endtask

  // Escreve um byte (espera haver espaço) e em seguida troca data_p_in por
  // lixo: o DUT precisa ter guardado o valor do momento da escrita.
  task automatic escreve(input logic [7:0] dado,
                         input logic [1:0] sel_esperado);
    while (buffer_full !== 1'b0) @(negedge clock_in);
    ciclo(1'b1, dado, sel_esperado);
    ciclo(1'b0, 8'($urandom), sel_esperado);
  endtask

  // Troca a taxa com o transmissor parado e dá tempo para o DUT
  // sincronizar a entrada antes do próximo byte.
  task automatic muda_taxa(input logic [1:0] sel);
    uart_rate_tx_sel = sel;
    repeat (10) @(negedge clock_in);
  endtask

  task automatic espera_ciclos(input int n);
    repeat (n) @(negedge clock_in);
  endtask

  // Espera todos os bytes pendentes saírem (com timeout)
  task automatic espera_transmissao(input string teste);
    realtime limite;
    limite = $realtime + 10_000.0
             + (esperado.size() + 1) * 11.0 * periodo_bit(2'b00);
    while ((esperado.size() != 0 || monitor_ocupado
            || uart_data_tx !== 1'b1) && $realtime < limite)
      @(negedge clock_in);
    if (esperado.size() != 0 || monitor_ocupado) begin
      erro($sformatf("%s: timeout, %0d byte(s) aceitos não foram enviados",
                     teste, esperado.size()));
      esperado.delete();
    end
    espera_ciclos(100);
  endtask

  //--------------------------------------------------------------------------
  // Teste 1 - reset e linha em repouso
  //--------------------------------------------------------------------------
  task automatic teste_reset_inicial();
    $display("\n=== Teste 1: reset e linha em repouso ===");
    reset_in = 1'b1;
    espera_ciclos(5);
    checa_x = 1'b1;
    if (uart_data_tx !== 1'b1)
      erro("uart_data_tx deveria ser 1 durante o reset");
    if (buffer_full !== 1'b0)
      erro("buffer_full deveria ser 0 durante o reset");
    reset_in = 1'b0;  // solto na descida, longe da borda ativa
    // 50 us mexendo em data_p_in SEM habilitar: nada pode ser transmitido
    repeat (5000) ciclo(1'b0, 8'($urandom), 2'b00);
    if (uart_data_tx !== 1'b1 || monitor_ocupado)
      erro("linha saiu do repouso sem data_p_en_in");
  endtask

  //--------------------------------------------------------------------------
  // Teste 2 - um quadro 0x55 + uma letra em cada taxa
  //--------------------------------------------------------------------------
  task automatic teste_cada_taxa();
    logic [7:0] letra;
    $display("\n=== Teste 2: cada taxa de transmissão ===");
    for (int s = 0; s < 4; s++) begin
      case (s)
        0: letra = "N";
        1: letra = "A";
        2: letra = "T";
        default: letra = "E";
      endcase
      muda_taxa(s[1:0]);
      escreve(8'h55, s[1:0]);   // 0x55: todo bit tem transição
      escreve(letra, s[1:0]);
      espera_transmissao("teste 2");
    end
  endtask

  //--------------------------------------------------------------------------
  // Teste 3 - padrões de canto escritos em ciclos consecutivos (rajada)
  //--------------------------------------------------------------------------
  task automatic teste_padroes_rajada();
    logic [7:0] p;
    $display("\n=== Teste 3: padrões em rajada (57600 bps) ===");
    muda_taxa(2'b11);
    for (int i = 0; i < 8; i++) begin
      case (i)
        0: p = 8'h00;  1: p = 8'hFF;  2: p = 8'h01;  3: p = 8'h80;
        4: p = 8'hA5;  5: p = 8'h5A;  6: p = 8'h7E;  default: p = 8'h81;
      endcase
      while (buffer_full !== 1'b0) @(negedge clock_in);
      ciclo(1'b1, p, 2'b11);
    end
    ciclo(1'b0, 8'h00, 2'b11);
    espera_transmissao("teste 3");
  endtask

  //--------------------------------------------------------------------------
  // Teste 4 - buffer cheio: data_p_en_in fica em 1 por 24 ciclos seguidos
  //--------------------------------------------------------------------------
  task automatic teste_buffer_cheio();
    int acc0, desc0;
    bit encheu;
    $display("\n=== Teste 4: buffer cheio (57600 bps) ===");
    muda_taxa(2'b11);
    acc0   = n_aceitos;
    desc0  = n_descartados;
    encheu = 1'b0;
    for (int i = 0; i < 24; i++) begin
      if (buffer_full === 1'b1) encheu = 1'b1;
      ciclo(1'b1, 8'h61 + i[7:0], 2'b11);   // 'a', 'b', 'c', ...
    end
    ciclo(1'b0, 8'h00, 2'b11);
    $display("[%t] rajada de 24 escritas: %0d aceitas, %0d descartadas",
             $realtime, n_aceitos - acc0, n_descartados - desc0);
    if (!encheu)
      $display("[%t] AVISO: buffer_full não chegou a subir", $realtime);
    // escreve assim que abrir espaço (testa a volta dos ponteiros)
    escreve("Z", 2'b11);
    espera_transmissao("teste 4");
  endtask

  //--------------------------------------------------------------------------
  // Teste 5 - troca de taxa durante um quadro (rajada com retenção do baud)
  //--------------------------------------------------------------------------
  // "N" sai em 9600. No meio dele a taxa muda 01 -> 10 -> 11 e "A", "T", "E"
  // são enfileirados. "N" não pode ser afetado; "A", "T" e "E" saem na taxa
  // que estiver selecionada quando o quadro deles começar (57600).
  task automatic teste_troca_taxa();
    $display("\n=== Teste 5: troca de taxa durante o quadro ===");
    muda_taxa(2'b00);
    escreve("N", 2'b00);
    wait (monitor_ocupado);                       // start bit de "N"
    espera_ate($realtime + 3.5 * periodo_bit(2'b00));
    @(negedge clock_in);
    uart_rate_tx_sel = 2'b01;  escreve("A", 2'b11);
    uart_rate_tx_sel = 2'b10;  escreve("T", 2'b11);
    uart_rate_tx_sel = 2'b11;  escreve("E", 2'b11);
    espera_transmissao("teste 5");
  endtask

  //--------------------------------------------------------------------------
  // Teste 6 - reset assíncrono no meio de uma transmissão
  //--------------------------------------------------------------------------
  task automatic teste_reset_no_meio();
    int quiet;
    $display("\n=== Teste 6: reset no meio da transmissão ===");
    muda_taxa(2'b10);
    escreve("R", 2'b10);   // 0x52: d3 = 0 -> linha em 0 na hora do reset
    escreve("S", 2'b10);
    escreve("T", 2'b10);
    escreve("U", 2'b10);
    wait (monitor_ocupado);                       // start bit de "R"
    espera_ate($realtime + 4.3 * periodo_bit(2'b10));
    @(negedge clock_in);
    #2;                     // 3 ns antes da borda de subida (fora do clock)
    reset_in = 1'b1;
    n_limpos += esperado.size();   // FIFO zerada: nada disso pode sair
    esperado.delete();
    #1;
    if (uart_data_tx !== 1'b1)
      erro("reset assíncrono: uart_data_tx não foi para 1 imediatamente");
    espera_ciclos(5);
    if (uart_data_tx !== 1'b1 || buffer_full !== 1'b0)
      erro("durante o reset: esperado uart_data_tx=1 e buffer_full=0");
    reset_in = 1'b0;
    // por um quadro inteiro na taxa mais lenta nada pode ser transmitido
    quiet = $rtoi(11.0 * periodo_bit(2'b00) / CLK_PERIOD);
    espera_ciclos(quiet);
    if (n_quadros_ok + n_abortados + n_limpos != n_aceitos)
      erro("bytes pendentes foram transmitidos depois do reset");
    // recuperação: tem que voltar a funcionar normalmente
    muda_taxa(2'b11);
    escreve("O", 2'b11);
    escreve("K", 2'b11);
    espera_transmissao("teste 6");
  endtask

  //--------------------------------------------------------------------------
  // Teste 7 - aleatório: taxa, dados, tamanho do grupo e intervalos
  //--------------------------------------------------------------------------
  task automatic teste_aleatorio();
    logic [1:0] sel;
    int n;
    $display("\n=== Teste 7: aleatório (semente %0d) ===", semente);
    for (int g = 0; g < N_GRUPOS; g++) begin
      sel = 2'($urandom_range(3, 0));
      n   = $urandom_range(3, 1);
      muda_taxa(sel);
      for (int i = 0; i < n; i++) begin
        escreve(8'($urandom), sel);
        espera_ciclos($urandom_range(30000, 0));  // até 300 us
      end
      espera_transmissao("teste 7");
    end
  endtask

  //--------------------------------------------------------------------------
  // Resumo
  //--------------------------------------------------------------------------
  task automatic resumo();
    if (n_erros == 0 && n_quadros_ok + n_abortados + n_limpos != n_aceitos)
      erro($sformatf("contagem não fecha: aceitos=%0d ok=%0d abort=%0d limpos=%0d",
                     n_aceitos, n_quadros_ok, n_abortados, n_limpos));
    $display("\n==================================================");
    $display(" Quadros recebidos corretos : %0d", n_quadros_ok);
    $display(" Escritas aceitas           : %0d", n_aceitos);
    $display(" Escritas descartadas (cheio): %0d", n_descartados);
    $display(" Bytes descartados por reset: %0d (+%0d quadro interrompido)",
             n_limpos, n_abortados);
    $display(" Erros                      : %0d", n_erros);
    if (n_erros == 0) $display(" >>> TESTE PASSOU <<<");
    else              $display(" >>> TESTE FALHOU <<<");
    $display("==================================================\n");
  endtask

  //--------------------------------------------------------------------------
  // Sequência principal
  //--------------------------------------------------------------------------
  initial begin : principal
    $timeformat(-6, 3, " us", 12);
    if (!$value$plusargs("SEED=%d", semente)) semente = 1;
    begin
      int unsigned s;
      s = semente;          // cópia: alguns simuladores alteram o argumento
      void'($urandom(s));
    end

    teste_reset_inicial();
    teste_cada_taxa();
    teste_padroes_rajada();
    teste_buffer_cheio();
    teste_troca_taxa();
    teste_reset_no_meio();
    teste_aleatorio();

    // silêncio final: nenhum quadro extra pode aparecer
    espera_ciclos($rtoi(11.0 * periodo_bit(2'b00) / CLK_PERIOD));
    resumo();
    $finish;
  end

  // Se o DUT travar (ex.: buffer_full preso em 1), não fica rodando para sempre
  initial begin : watchdog
    #(WATCHDOG_NS);
    erro("WATCHDOG: tempo máximo de simulação estourado (DUT travado?)");
    resumo();
    $finish;
  end

endmodule

