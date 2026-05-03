`timescale 1ns / 1ps

module loopback(
    switches,
    leds,
    rs232_tx,
    rs232_rx,
    reset,
    clk
);

    input reset;      // Active-low board reset.
    input clk;        // 100 MHz Anvyl oscillator.
    input [7:0] switches;
    output [7:0] leds;
    input rs232_rx;
    output rs232_tx;

    wire [7:0] pb_port_id;
    wire [7:0] pb_out_port;
    reg [7:0] pb_in_port;
    wire pb_read_strobe;
    wire pb_write_strobe;

    wire pb_reset;
    wire pb_interrupt;

    wire write_to_uart;
    wire uart_buffer_full;
    wire uart_data_present;
    reg read_from_uart;
    wire uart_reset;
    wire [7:0] uart_rx_data;

    wire write_to_leds;
    wire led_reset;

    reg [7:0] command_out;
    reg [7:0] msg_num_out;
    wire [7:0] status_in;

    assign status_in = 8'h00;

    assign led_reset = ~reset;
    led_driver_wrapper led_driver (
        .led_value(pb_out_port),
        .leds(leds),
        .write_to_leds(write_to_leds),
        .reset(led_reset),
        .clk(clk)
    );

    assign uart_reset = ~reset;
    rs232_uart UART (
        .tx_data_in(pb_out_port),
        .write_tx_data(write_to_uart),
        .tx_buffer_full(uart_buffer_full),
        .rx_data_out(uart_rx_data),
        .read_rx_data_ack(read_from_uart),
        .rx_data_present(uart_data_present),
        .rs232_tx(rs232_tx),
        .rs232_rx(rs232_rx),
        .reset(uart_reset),
        .clk(clk)
    );

    assign pb_reset = ~reset;
    assign pb_interrupt = 1'b0;
    picoblaze_final_project CPU (
        .port_id(pb_port_id),
        .read_strobe(pb_read_strobe),
        .in_port(pb_in_port),
        .write_strobe(pb_write_strobe),
        .out_port(pb_out_port),
        .interrupt(pb_interrupt),
        .interrupt_ack(),
        .reset(pb_reset),
        .clk(clk)
    );

    assign write_to_leds = pb_write_strobe & (pb_port_id == 8'h01);
    assign write_to_uart = pb_write_strobe & (pb_port_id == 8'h03);

    always @(posedge clk or posedge pb_reset) begin
        if (pb_reset) begin
            pb_in_port <= 8'h00;
            read_from_uart <= 1'b0;
            command_out <= 8'h00;
            msg_num_out <= 8'h00;
        end else begin
            case (pb_port_id)
                8'h00: pb_in_port <= switches;
                8'h02: pb_in_port <= uart_rx_data;
                8'h04: pb_in_port <= {7'b0000000, uart_data_present};
                8'h05: pb_in_port <= {7'b0000000, uart_buffer_full};
                8'h08: pb_in_port <= status_in;
                default: pb_in_port <= 8'h00;
            endcase

            read_from_uart <= pb_read_strobe & (pb_port_id == 8'h02);

            if (pb_write_strobe & (pb_port_id == 8'h06)) begin
                command_out <= pb_out_port;
            end
            if (pb_write_strobe & (pb_port_id == 8'h07)) begin
                msg_num_out <= pb_out_port;
            end
        end
    end

endmodule
