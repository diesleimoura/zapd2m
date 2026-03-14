# Changelog - zapd2m

Todas as mudanças relevantes deste projeto serão documentadas neste arquivo.

## [11/03/2026] - Versão 1.4.0

### Adicionado

- **Extração Nativa de PDF**: Implementação da biblioteca `pdf-parse` na Edge Function `process-document`, permitindo a extração de texto local e nativa sem depender da API de Visão da OpenAI para arquivos PDF.
- **Suporte a Novos Formatos**: Adicionado suporte para processamento de arquivos `.md` (Markdown) e `.json` na Base de Conhecimento.
- **Dicas de Formatação**: Nova interface no modal de upload com recomendações de uso de Markdown para melhorar o desempenho da IA.

### Melhorias

- **Tratamento de Erros da OpenAI**: Melhoria na captura e exibição de erros detalhados da API da OpenAI, facilitando o diagnóstico de problemas de cota ou chave de API.
- **Detecção de Tipos de Arquivo**: Refatoração da lógica de decisão de extração baseada na extensão do arquivo para maior precisão e economia de tokens.

### Corrigido

- **Erro 500 no Processamento de PDF**: Resolvido o erro de processamento causado pela tentativa de enviar buffers de PDF codificados em base64 como imagens para a API da OpenAI.

---

## [09/03/2026] - Versão 1.3.0

- **HashRouter & Core Routing**: Substituição do roteamento por hash para compatibilidade universal com servidores `index.html`.
- **URLs de Redirecionamento Supabase**: Atualização dos links de recuperação de senha e confirmação de e-mail para o formato compatível com hash.

## [08/03/2026] - Versão 1.2.0

### Melhorias

- **Experiência de Carregamento Instantâneo**: Implementação de `localStorage` em todos os hooks de busca de dados (`useDashboardMetrics`, `useConversations`, `useMessages`, `useKanban`, `useContacts`, `useWhatsAppInstances`, `useSchedules`, `useAISettings`, `useUserPreferences`, `useUserRole`, `usePlans`, `usePlanLimits`).
- **Padrão Stale-While-Revalidade**: O sistema agora exibe os últimos dados salvos imediatamente ao abrir qualquer página, realizando a atualização silenciosa em segundo plano.
- **Persistência de Admin**: Abas administrativas (Usuários, Roadmap, Métricas, Evolution API, Configurações do Sistema e Botão Flutuante) agora carregam instantaneamente.
- **Remoção de Animações Bloqueantes**: Substituição de componentes `framer-motion` (`motion.div`, `AnimatePresence`) por elementos HTML padrão nas páginas de Dashboard, Admin e Sidebar.
- **Global CSS Performance**: Desativado globalmente `transition-duration` e `animation-duration` para 0s em `index.css`.
- **Renderização de Menus**: A aba "Administração" na sidebar agora aparece no exato momento do carregamento da página, eliminando o delay de verificação de cargo administrativo.
- **Fluxo de Chat**: O histórico de mensagens agora persiste localmente por conversa, permitindo alternar entre chats de forma instantânea.
- **Loading Spinners & Pre-loaders**: Ocultação global de spinners de carregamento (`animate-spin`) e remoção de estados de carregamento bloqueantes (`loading: true`).
- **Transições de Página**: Eliminadas transições de entrada/saída que causavam micro-percepção de lentidão.
- **Tempo de Pintura Inicial (FCP)**: Reduzido para próximo de zero para dados conhecidos.
- **Interatividade**: Páginas como Kanban e Conversas agora são interativas desde o primeiro frame.
- **Percepção do Usuário**: Sensação de "aplicativo nativo" com resposta imediata a todos os cliques.
- **Compatibilidade com Hospedagem**: Migração para `HashRouter` para suporte total em hospedagens compartilhadas (Apache/cPanel) sem necessidade de redirecionamento no servidor.
- **Configuração de Build Progressiva**: Definição de caminhos relativos (`base: "./"`) no Vite para carregamento robusto de assets em qualquer subdiretório.
- **Navegação Suave (Landing Page)**: Implementação de scroll suave para âncoras internas, evitando conflitos com o sistema de hash do roteador.

### Adicionado

- **Camada de Cache Local (Persistence Layer)**: Implementação de `localStorage` em todos os hooks de busca de dados (`useDashboardMetrics`, `useConversations`, `useMessages`, `useKanban`, `useContacts`, `useWhatsAppInstances`, `useSchedules`, `useAISettings`, `useUserPreferences`, `useUserRole`, `usePlans`, `usePlanLimits`).
- **Padrão Stale-While-Revalidade**: O sistema agora exibe os últimos dados salvos imediatamente ao abrir qualquer página, realizando a atualização silenciosa em segundo plano.
- **Persistência de Admin**: Abas administrativas (Usuários, Roadmap, Métricas, Evolution API, Configurações do Sistema e Botão Flutuante) agora carregam instantaneamente.

### Alterado

- **Remoção de Animações Bloqueantes**: Substituição de componentes `framer-motion` (`motion.div`, `AnimatePresence`) por elementos HTML padrão nas páginas de Dashboard, Admin e Sidebar.
- **Global CSS Performance**: Desativado globalmente `transition-duration` e `animation-duration` para 0s em `index.css`.
- **Renderização de Menus**: A aba "Administração" na sidebar agora aparece no exato momento do carregamento da página, eliminando o delay de verificação de cargo administrativo.
- **Fluxo de Chat**: O histórico de mensagens agora persiste localmente por conversa, permitindo alternar entre chats de forma instantânea.

### Removido

- **Loading Spinners & Pre-loaders**: Ocultação global de spinners de carregamento (`animate-spin`) e remoção de estados de carregamento bloqueantes (`loading: true`).
- **Transições de Página**: Eliminadas transições de entrada/saída que causavam micro-percepção de lentidão.

### Resultados de Performance

- **Tempo de Pintura Inicial (FCP)**: Reduzido para próximo de zero para dados conhecidos.
- **Interatividade**: Páginas como Kanban e Conversas agora são interativas desde o primeiro frame.
- **Percepção do Usuário**: Sensação de "aplicativo nativo" com resposta imediata a todos os cliques.

## [07/03/2026] - Versão 1.1.0

### Adicionado

- Inclusão de **2 novos arquivos SQL** na pasta `migrations`.
- Inclusão de **novos arquivos de instruções (.md)** na pasta `guia`.

---

_zapd2m - afCode_
