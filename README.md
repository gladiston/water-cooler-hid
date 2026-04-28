# CPU Cooler Display para Linux

Este projeto oferece uma solução para exibir a temperatura da CPU em displays de Water Coolers no Linux, especialmente para dispositivos que possuem apenas software de controle para Windows.

O script captura a temperatura da CPU em tempo real e a envia para o display do cooler a cada segundo. Foi testado com o Water Cooler Rise Mode Aura Ice Black, mas deve ser compatível com outros dispositivos que utilizam comunicação HID similar.

## Funcionalidades

- **Monitoramento em Tempo Real:** Exibe a temperatura atual da CPU no display do seu Water Cooler.
- **Fácil Instalação:** Scripts de instalação automatizada para usuário local ou para todo o sistema.
- **Inicialização Automática:** Roda como um serviço do `systemd`, iniciando automaticamente com o sistema.
- **Alta Compatibilidade:** Requer apenas Python e bibliotecas padrão, sem necessidade de softwares proprietários.
- **Customizável:** Permite fácil alteração dos IDs do dispositivo e da fonte de temperatura da CPU.

## Pré-requisitos

Antes de começar, certifique-se de que você tem o `python3` e o `pip` instalados. Você também precisará das seguintes bibliotecas Python:

- `hidapi` (python-hid)
- `psutil` (python-psutil)

Você pode instalar as dependências em distribuições baseadas em Debian/Ubuntu com o seguinte comando:

```bash
sudo apt update -y
sudo apt install python3 python3-pip libhidapi-dev -y
pip3 install hidapi psutil -y
```

## Encontre os IDs do seu Dispositivo

Primeiro, você precisa identificar o `Vendor ID` e o `Product ID` do seu Water Cooler. Conecte o dispositivo na porta USB e execute o comando:

```bash
lsusb
```

A saída será algo como:
`Bus 001 Device 005: ID aabb:ccdd My Cooler Device`

Neste exemplo, o `Vendor ID` é `aabb` e o `Product ID` é `ccdd`. Anote esses valores.

A saída para oWater Cooler Rise Mode Aura Ice Black será algo como:
`Bus 001 Device 010: ID aa88:8666 铭研科技 温度显示HID设备`

Neste exemplo, o `Vendor ID` é `aa88` e o `Product ID` é `8666`. Anote esses valores.

Agora que você sabe que ele existe em seu sistema, vamos a instalação

## Instalação
Vamos fazer o download do repositório:  
```bash
cd /usr/local/src
sudo git clone https://github.com/gladiston/water-cooler-hid.git
cd water-cooler-hid/ 
```
Dê permissão de execução aos scripts:
```bash
sudo chmod a+x *.sh
sudo chmod a+x *.py
```
Pronto!  
Agora ele está instalado, porém ainda não está configurado.  

## CONFIGURAÇÃO
Escolha o Método de Instalação, mas antes de prosseguir, tenha certeza de estar no diretório correto, execute:  
```bash
cd /usr/local/src/water-cooler-hid
```  
Depois, escolha o método de instalação apenas para você(usuário) ou para o sistema. Se vocÊ instalar para você, o script só funcionará com você ligado, o que é o padrão para desktops pessoais. Porém, temos a opção de instalar para o sistema e daí o dsplay é ligado quando o sistema operacional termina o processo de boot, isso é bem mais útil para servidores, mas pode valer a pena também para programadores que agendam processos sem haver nenhuma pessoa logado no sistema.  

### a) Instalação Automatizada para Usuário (Recomendado)

Este método instala o serviço para o seu usuário atual e não requer privilégios de `root` para a maior parte do processo.  

Execute o script e siga as instruções:
```bash
./install-user.sh
```
O script solicitará o `Vendor ID` e o `Product ID` que você anotou. Ele criará a regra `udev` necessária, copiará os arquivos e ativará o serviço `systemd` para o seu usuário.

### b) Instalação Automatizada para o Sistema (System-wide)

Este método instala o serviço para todos os usuários do sistema, execute o script abaixo com `sudo`:
```bash
sudo ./install-system.sh
```
O script solicitará os IDs, configurará a regra `udev`, instalará os arquivos nos diretórios do sistema (`/usr/local/bin` e `/etc/systemd/system`) e ativará o serviço globalmente.

## Uso e Verificação

Após a instalação, o serviço já estará rodando. Para verificar o status:

-   **Para instalação de usuário:**
    ```bash
    systemctl --user status cpu-cooler
    ```
-   **Para instalação de sistema:**
    ```bash
    systemctl status cpu-cooler.service
    ```

## Configuração Avançada

### Fonte da Temperatura da CPU

Por padrão, o script utiliza o sensor `k10temp`, comum em CPUs AMD. A linha relevante em `cpu_cooler.py` é:

```python
temp = psutil.sensors_temperatures()['k10temp'][0].current
```

Se você possui uma CPU Intel ou deseja usar um sensor diferente, pode explorar os sensores disponíveis executando um script Python com `import psutil; print(psutil.sensors_temperatures())` e ajustar a linha acima conforme necessário.

### Edição Manual dos IDs do Dispositivo

Se preferir, você pode editar o arquivo `cpu_cooler.py` e inserir seus `VENDOR_ID` e `PRODUCT_ID` diretamente antes de executar os scripts de instalação:

```python
VENDOR_ID = 0xSUA_ID_DE_FABRICANTE
PRODUCT_ID = 0xSUA_ID_DE_PRODUTO
```

## 🗑️ Desinstalação
Antes de remover, tenha certeza de estar no diretório correto, execute:  
```bash
cd /usr/local/src/water-cooler-hid
```
### a) Desinstalação de Usuário
```bash
./install-user.sh --uninstall
```

#### b) Desinstalação de Sistema
```bash
sudo ./install-system.sh --uninstall
```
Esses comandos removem serviços, scripts e (no modo sistema) a regra `udev`.

## Solução de Problemas

-   **Dispositivo não encontrado:** Verifique se os `VENDOR_ID` e `PRODUCT_ID` estão corretos. Desconecte e reconecte o dispositivo USB após a criação da regra `udev`.
-   **Erro de permissão:** Se você optou pela instalação manual e não criou a regra `udev`, o script precisará ser executado com `sudo`. A instalação automatizada cuida disso para você.
-   **Serviço não inicia:** Use o comando `journalctl --user -u cpu-cooler` (instalação de usuário) ou `journalctl -u cpu-cooler.service` (instalação de sistema) para ver os logs de erro.

---

## Atualizações Importantes (compatibilidade e modos)

### Compatibilidade com diferentes versões do `hid`
O script `cpu_cooler.py` foi atualizado para funcionar com **ambas** as APIs encontradas no Linux:
- `hid.Device(...)`
- `hid.device()` + `open_path(...)`

Isso evita erros como:
```
AttributeError: module 'hid' has no attribute 'Device'
```
e garante funcionamento tanto com pacotes mais antigos quanto mais novos.

### Comportamento resiliente (systemd)
O script **não encerra** se o dispositivo HID ainda não estiver disponível no boot ou após reconexão USB.
Ele tenta reconectar automaticamente, mantendo o serviço ativo no `systemd`.

### Modos de exibição
Agora é possível escolher o que será exibido no display:
- `temp` — Temperatura da CPU (padrão)
- `cpu` — Uso da CPU em %
- `ram` — Uso da memória RAM em %

### Aviso importante sobre o display
* A **linha inferior do display** que no meu modelo mostra `"Temp/C"` é **FIXA do hardware** e **não pode ser alterada** pelo script.  
* Ao usar os modos `cpu` ou `ram`, o **valor numérico estará correto**, mas o texto inferior continuará exibindo `"Temp/C"`.

### Advertências importantes
- `install-user.sh` **não deve ser executado com sudo**.  
  Ele aborta se for executado como root para evitar problemas com `systemd --user`.
- `install-system.sh` **deve ser executado com sudo**.
