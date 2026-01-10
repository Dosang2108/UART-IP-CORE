# UART Controller IP Core

Dự án này cung cấp một bộ điều khiển UART (Universal Asynchronous Receiver-Transmitter) hoàn chỉnh được viết bằng Verilog. Thiết kế bao gồm bộ đệm FIFO, logic tạo tốc độ Baud tự động, và khả năng tích hợp giao tiếp AXI4-Lite.

## 🌟 Tính Năng Chính

* **Full-duplex UART:** Truyền và nhận dữ liệu đồng thời.
* **Cấu hình linh hoạt:** Dễ dàng thay đổi `BAUD_RATE`, `DATA_WIDTH`, và tần số xung nhịp hệ thống thông qua tham số (parameter).
* **Deep Buffering:** Tích hợp FIFO bất đồng bộ (Asynchronous FIFO) cho cả đường truyền (TX) và nhận (RX) giúp CPU không bị nghẽn cổ chai.
* **Cơ chế an toàn & Lọc nhiễu:**
    * RX sử dụng bộ đồng bộ hóa 2 tầng (2-stage synchronizer) để chống hiện tượng Metastability.
    * Oversampling (lấy mẫu dư) 16 lần để đảm bảo bắt dữ liệu chính xác.
* **Phát hiện lỗi:** Hỗ trợ phát hiện lỗi Frame (Frame Error) và lỗi Timeout.
* **Thống kê (Statistics):** Tích hợp sẵn bộ đếm số byte đã truyền/nhận và số lượng lỗi phát sinh.
* **Giao diện AXI4-Lite:** Có sẵn module `axi_ctrl.v` để bọc (wrap) core UART, cho phép giao tiếp dễ dàng với vi xử lý qua bus AXI.

## 📂 Cấu Trúc File

* `uart_top.v`: Module cấp cao nhất, kết nối các thành phần con và cung cấp giao diện CPU đơn giản.
* `UART_TX.v`: Máy trạng thái truyền dữ liệu (Serializer).
* `UART_RX.v`: Máy trạng thái nhận dữ liệu (Deserializer) với bộ lọc nhiễu.
* `baudrate_gen.v`: Bộ chia xung nhịp tạo tín hiệu enable cho TX/RX.
* `FIFO.v` (`asyn_fifo`): Bộ nhớ đệm FIFO hỗ trợ chuyển đổi miền clock (Clock Domain Crossing).
* `axi_ctrl.v`: Giao diện điều khiển AXI4-Lite Slave.

## ⚙️ Thông Số Kỹ Thuật (Default Configuration)

Hiện tại, các cấu hình giao thức vật lý đang được thiết lập mặc định trong code (có thể thay đổi trong `UART_TX.v` và `UART_RX.v`):
* **Data Bits:** 8 bits.
* **Parity:** Even Parity (Chẵn).
* **Stop Bits:** 2 Stop Bits.

### Parameters (uart_top)

| Tham số | Giá trị mặc định | Mô tả |
| :--- | :--- | :--- |
| `DATA_WIDTH` | 8 | Độ rộng dữ liệu (bits). |
| `INTERNAL_CLOCK` | 125,000,000 | Tần số xung nhịp đầu vào (Hz). |
| `BAUD_RATE` | 115,200 | Tốc độ Baud mong muốn. |
| `FIFO_DEPTH` | 16 | Độ sâu của bộ đệm FIFO. |

## 🔌 Giao Diện Tín Hiệu (Ports)

### Clock & Reset
* `clk`: Clock hệ thống.
* `rst_n`: Reset tích cực thấp (Active low).

### UART Physical Interface
* `rxd`: Tín hiệu nhận dữ liệu nối tiếp.
* `txd`: Tín hiệu truyền dữ liệu nối tiếp.

### CPU/User Interface
* **TX Channel:**
    * `cpu_tx_data`: Dữ liệu cần gửi.
    * `cpu_tx_valid`: Tín hiệu báo dữ liệu hợp lệ (Write Request).
    * `cpu_tx_ready`: Báo FIFO TX sẵn sàng nhận (không đầy).
* **RX Channel:**
    * `cpu_rx_data`: Dữ liệu nhận được.
    * `cpu_rx_valid`: Tín hiệu báo có dữ liệu (FIFO không rỗng).
    * `cpu_rx_ready`: Tín hiệu báo CPU đã đọc xong (Read Acknowledge).

### Status & Error
* `tx_busy` / `rx_busy`: Trạng thái bận.
* `tx_fifo_full` / `rx_fifo_empty`: Cờ trạng thái FIFO.
* `frame_error`: Cờ báo lỗi khung truyền (Stop bit không đúng).
* `timeout_error`: Cờ báo quá thời gian chờ nhận.

## Hướng Dẫn Sử Dụng (Instantiation Template)


```verilog
uart_top #(
    .DATA_WIDTH(8),
    .INTERNAL_CLOCK(100000000), // Ví dụ clock 100MHz
    .BAUD_RATE(9600),           // Ví dụ baud 9600
    .FIFO_DEPTH(32)
) my_uart_inst (
    .clk(sys_clk),
    .rst_n(sys_rst_n),
    
    // UART Physical
    .rxd(uart_rxd),
    .txd(uart_txd),
    
    // TX Interface
    .cpu_tx_data(tx_data_reg),
    .cpu_tx_valid(tx_valid_reg),
    .cpu_tx_ready(tx_ready_wire),
    
    // RX Interface
    .cpu_rx_data(rx_data_wire),
    .cpu_rx_valid(rx_valid_wire),
    .cpu_rx_ready(rx_ready_reg),
    
    // Status
    .tx_busy(),
    .rx_busy(),
    .tx_fifo_full(),
    .rx_fifo_empty(),
    .frame_error(led_error_frame),
    .timeout_error(led_error_timeout)
);
