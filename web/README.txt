ApexFlow Web — painel remoto + mockups de design (v0.18.0)

1) PAINEL REMOTO (de verdade, fala com o app no jogo)
   Requer Python 3 (só biblioteca padrão, nada para instalar).

   a) No jogo: abra o ApexFlow > Ajustes > "Web remota" e ATIVE.
      Anote o token se configurar um (se vazio, sem senha).
   b) No PC: rode
        python panel_server.py
      e abra  http://localhost:8080/panel.html
   c) No celular (mesma Wi-Fi): abra  http://<ip-do-pc>:8080/panel.html
      (o servidor mostra o endereço ao iniciar).
   d) Para live/OBS: adicione panel.html como Browser Source.

   O que dá para fazer: ver bandeira/posição/volta/classificação ao vivo,
   trocar preset, mexer em agressividade/ritmo/dificuldade, ligar/desligar
   largada e estratégia, forçar caution, testar a voz, salvar/resetar config.

   Arquivos trocados com o jogo (pasta Documents/Assetto Corsa):
     RaceFlow_webui_status.json  (app -> painel, a cada 0.5s)
     RaceFlow_webui_cmd.json      (painel -> app, comandos)

2) MOCKUPS (só visual, para escolher o design do app)
   Com o mesmo servidor rodando, abra:
     http://localhost:8080/mock-a-console.html   (A · trilho + inspetor)
     http://localhost:8080/mock-b-wizard.html    (B · assistente 3 passos)
     http://localhost:8080/mock-c-cards.html     (C · cartões estilo RaceLab)
   Dá para abrir direto com duplo clique também (sem servidor).
   Escolha um e avise — o vencedor vira o layout do app no jogo.
