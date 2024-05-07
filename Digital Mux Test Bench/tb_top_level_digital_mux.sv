`timescale 1ns / 10ps

// Top-level testbench module for digital multiplexer
module tb_top_level_digital_mux();

    // Define constants for digital multiplexer configuration
    localparam PIN_COUNT = 20;  // Maximum: 32
    localparam FUNC_COUNT = 4;  // Maximum: 4
    localparam BIT_COUNT = 2;   // Maximum: 2
    localparam REG_COUNT = 2;   // Maximum: 2

    // Clock configuration
    localparam CLOCK_CYCLE = 10;

    // Transaction count for the execute_transactions task
    localparam TRANSACTION_COUNT = 16;
    int current_index;

    // Clock and reset signals
    logic system_clk;
    logic system_reset_n;
    int testcase_number = 0;

    // APB interface signals
    logic apb_select, apb_enable, apb_write, apb_error, apb_ready;
    logic [3:0] apb_strb;
    logic [31:0] apb_address, apb_write_data, apb_read_data;
    logic [31:0] expected_read_data;
    logic [PIN_COUNT * FUNC_COUNT - 1:0] module_inputs;
    logic [PIN_COUNT * FUNC_COUNT - 1:0] output_enable_signals;
    logic [PIN_COUNT * FUNC_COUNT - 1:0] module_outputs;
    logic [PIN_COUNT - 1:0] iopad_outputs;
    logic [PIN_COUNT - 1:0] ff_inputs;
    logic [PIN_COUNT - 1:0] ff_output_enables;
    logic [PIN_COUNT - 1:0] expected_ff_outputs;

    int test_case_number = 0;
    //input logic is_input_sync;
    //logic monitored_signal, monitored_enable;

    // Simulation of input signals from pins or peripherals
    logic dataline_sim_input;  // Simulates input data from a peripheral
    localparam SIGNAL_PERIOD = 20 * CLOCK_CYCLE;
    logic [31:0] data_stream, monitored_data, additional_monitored_data;
    logic monitored_line;

    // Definition of the APB bus structure
    typedef struct {
        logic [31:0] ADDR;
        logic [31:0] DATA;
        logic [3:0] STRB;
        logic WRITE;
        logic EXPECTED_ERROR;
    } APB_TRANSACTION;

    // Clock generation block
    always begin
        system_clk = 1'b0;
        #(CLOCK_CYCLE / 2);  // Wait for half the clock period
        system_clk = 1'b1;
        #(CLOCK_CYCLE / 2);  // Complete the clock cycle
    end

    // Reset device under test task
    task reset_device_under_test;
    begin
        system_reset_n = 1'b0;  // Assert reset
        @(posedge system_clk);
        @(posedge system_clk);  // Hold reset for two clock cycles
        @(negedge system_clk);  // Release reset after the falling edge
        system_reset_n = 1'b1;
        @(negedge system_clk);
        @(negedge system_clk);  // Stabilize system post-reset
    end
    endtask

    // Task to reset the APB bus interface signals to default states
task reset_apb_bus;
begin
    @(posedge system_clk);
    #(CLOCK_CYCLE / 10); // Short delay for timing margins
    apb_select = 1'b0;
    apb_enable = 1'b0;
    apb_write = 1'b0;  // Default to read mode
    apb_address = 32'b0;
    apb_write_data = 32'b0;
    apb_strb = 4'b0;
    module_inputs = '0;
    output_enable_signals = '0;
    iopad_outputs = '0;
    @(negedge system_clk);
end
endtask

// Task to execute APB transactions
task execute_apb_transactions;
    input APB_TRANSACTION transaction;
    int i;
begin
    reset_apb_bus();
    @(posedge system_clk);
    #(CLOCK_CYCLE / 10);  // Delay to satisfy hold times
    apb_select = 1'b1;

    for (i = 0; i < 1; i++) begin
        apb_enable = 1'b0;
        apb_address = transaction.ADDR;
        apb_write = transaction.WRITE;
        apb_strb = transaction.STRB;
        if (transaction.WRITE) begin
            apb_write_data = transaction.DATA;
        end
        else begin
            apb_write_data = 32'b0;
            expected_read_data = transaction.DATA;
        end

        @(posedge system_clk)
        #(CLOCK_CYCLE / 10);
        apb_enable = 1'b1;
        if (apb_error != transaction.EXPECTED_ERROR)
            $error("Mismatch in APB error signal during testcase #%d", test_case_number);
        if (!apb_write && apb_error != 1'b1 && expected_read_data != apb_read_data)
            $error("Data mismatch in APB read during testcase #%d", test_case_number);
    end

    reset_apb_bus();
end
endtask

// Task to send and monitor signals, distinguishing data paths based on synchronization
task send_and_monitor_signals;
    input logic [31:0] data_to_send;
    input logic is_input_sync;  // Determines synchronization requirement
    input integer signal_offset;
begin
    int i, j;
    logic monitored_signal, monitored_enable;

    fork
        // Thread for sending data
        begin
            if (is_input_sync)
                @(negedge system_clk); // Synchronize with the negative clock edge for inputs

            for (i = 0; i < 32; i++) begin
                dataline_sim_input = data_to_send[i];
                if (!is_input_sync) begin
                    iopad_outputs[current_index] = dataline_sim_input;
                end
                else begin
                    module_inputs[current_index * FUNC_COUNT + signal_offset] = dataline_sim_input;
                    output_enable_signals[current_index * FUNC_COUNT + signal_offset] = dataline_sim_input;
                end
                #(SIGNAL_PERIOD);
            end
        end

        // Thread for monitoring data
        begin
            #(SIGNAL_PERIOD / 2 + 1);  // Offset for monitoring to catch the signal part-way through its state

            for (j = 0; j < 32; j++) begin
                if (is_input_sync) begin
                    monitored_signal = ff_inputs[current_index];
                    monitored_enable = ff_output_enables[current_index];
                    additional_monitored_data[j] = monitored_enable;
                end
                else begin
                    monitored_signal = module_outputs[current_index * FUNC_COUNT + signal_offset];
                end

                monitored_data[j] = monitored_signal;
                if (monitored_data[j] != data_to_send[j]) begin
                    $error("Signal mismatch at bit %d: expected %b, found %b", j, data_to_send[j], monitored_data[j]);
                end
                #(SIGNAL_PERIOD);
            end
        end
    //join
//end
//endtask


// Continuation of the task for sending and monitoring signals
    // Monitoring data thread
    begin
      //input logic is_input_sync;  // Determines synchronization requirement
      //genvar  j;
        // Apply a timing offset to catch the signal midway
        #(SIGNAL_PERIOD / 2 + 1);  

        // Loop through each bit of the data
        for (j = 0; j < 32; j++) begin
            // Collect data depending on the synchronization requirement
            if (is_input_sync) begin
                monitored_signal = ff_inputs[current_index];
                monitored_enable = ff_output_enables[current_index];
                additional_monitored_data[j] = monitored_enable;
            end 
            else begin
                monitored_signal = module_outputs[current_index * FUNC_COUNT + signal_offset];
            end 

            // Store the monitored signal
            monitored_data[j] = monitored_signal;

            // Verify the integrity of the monitored data against the expected data
            if (monitored_data[j] != data_to_send[j]) begin
                $error("Signal mismatch at bit %d: expected %b, found %b in %s", j, data_to_send[j], monitored_data[j],
                       is_input_sync ? "input path" : "output path");
            end 
        
        // Maintain timing for monitoring
        #(SIGNAL_PERIOD);  
    end
end
    join 
end 
endtask


// Digital multiplexer (DUT) instantiation
top_level_digital_mux DUT (
    .CLK(system_clk),
    .RESETn(system_reset_n),
    .PSEL(apb_select),
    .PENABLE(apb_enable),
    .PWRITE(apb_write),
    .PSLVERR(apb_error),
    .PREADY(apb_ready),
    .PSTRB(apb_strb),
    .PADDR(apb_address),
    .PWDATA(apb_write_data),
    .PRDATA(apb_read_data),

    .from_module(module_inputs),
    .output_enable(output_enable_signals),
    .to_module(module_outputs),

    .to_module_iopad(iopad_outputs),
    .from_module_ff(ff_inputs),
    .output_en_ff(ff_output_enables)
);

// Define parameters for the digital multiplexer (DUT)
defparam DUT.PIN_COUNT = PIN_COUNT;
defparam DUT.FUNC_COUNT = FUNC_COUNT;
defparam DUT.BIT_COUNT = BIT_COUNT;
defparam DUT.REG_COUNT = REG_COUNT;

// Defining APB transactions for testing various scenarios

APB_TRANSACTION transactions[];

initial begin    
    transactions = new[TRANSACTION_COUNT];

    // Standard transaction setup
    transactions[0].ADDR = 32'h80050000;
    transactions[0].DATA = 32'h00000000;
    transactions[0].STRB = 4'b1111;
    transactions[0].WRITE = 1'b1;
    transactions[0].EXPECTED_ERROR = 1'b0;

    // Reading with STRB all zeros, expect no slave error
    transactions[1].ADDR = 32'h80050000;
    transactions[1].DATA = 32'h00000000;
    transactions[1].STRB = 4'b0;
    transactions[1].WRITE = 1'b0;
    transactions[1].EXPECTED_ERROR = 1'b0;

    // Writing and then reading to ensure data integrity
    transactions[2].ADDR = 32'h80050000;
    transactions[2].DATA = 32'h000FFFFF;
    transactions[2].STRB = 4'b1111;
    transactions[2].WRITE = 1'b1;
    transactions[2].EXPECTED_ERROR = 1'b0;
    transactions[3].ADDR = 32'h80050000;
    transactions[3].DATA = 32'h000FFFFF;
    transactions[3].STRB = 4'b0;
    transactions[3].WRITE = 1'b0;
    transactions[3].EXPECTED_ERROR = 1'b0;

    // Testing with different address and ensuring an error is flagged
    transactions[4].ADDR = 32'h80050008;
    transactions[4].DATA = 32'h000FFFFF;
    transactions[4].STRB = 4'b1111;
    transactions[4].WRITE = 1'b1;
    transactions[4].EXPECTED_ERROR = 1'b1;

    // Incorrect setup for reading operation
    transactions[5].ADDR = 32'h80050000;
    transactions[5].DATA = 32'h000FFFFF;
    transactions[5].STRB = 4'b1111;  // Improper STRB for a read operation
    transactions[5].WRITE = 1'b0;
    transactions[5].EXPECTED_ERROR = 1'b1;

    // Partial byte write operation
    transactions[6].ADDR = 32'h80050000;
    transactions[6].DATA = 32'hFFFFFFFF;
    transactions[6].STRB = 4'b0110;
    transactions[6].WRITE = 1'b1;
    transactions[6].EXPECTED_ERROR = 1'b0;

    // Read operation with all zeros in PSTRB, expecting no errors
    transactions[7].ADDR = 32'h80050000;
    transactions[7].DATA = 32'h00FFFF00;
    transactions[7].STRB = 4'b0000;
    transactions[7].WRITE = 1'b0;
    transactions[7].EXPECTED_ERROR = 1'b0;

    // Detailed tests with specific register configurations
    transactions[8].ADDR = 32'h80050000;
    transactions[8].DATA = 32'h55555555;  // Setting specific functional select bits
    transactions[8].STRB = 4'b1111;
    transactions[8].WRITE = 1'b1;
    transactions[8].EXPECTED_ERROR = 1'b0;

    transactions[9].ADDR = 32'h80050004;
    transactions[9].DATA = 32'h55555555;
    transactions[9].STRB = 4'b0001;
    transactions[9].WRITE = 1'b1;
    transactions[9].EXPECTED_ERROR = 1'b0;

    transactions[10].ADDR = 32'h80050000;
    transactions[10].DATA = 32'h55555555;
    transactions[10].STRB = 4'b0;
    transactions[10].WRITE = 1'b0;
    transactions[10].EXPECTED_ERROR = 1'b0;

    transactions[11].ADDR = 32'h80050004;
    transactions[11].DATA = 32'h00000055;
    transactions[11].STRB = 4'b0;
    transactions[11].WRITE = 1'b0;
    transactions[11].EXPECTED_ERROR = 1'b0;

    // Testing another set of register writes and reads
    transactions[12].ADDR = 32'h80050000;
    transactions[12].DATA = 32'haaaaaaaa;
    transactions[12].STRB = 4'b1111;
    transactions[12].WRITE = 1'b1;
    transactions[12].EXPECTED_ERROR = 1'b0;

    transactions[13].ADDR = 32'h80050004;
    transactions[13].DATA = 32'haaaaaaaa;
    transactions[13].STRB = 4'b0001;
    transactions[13].WRITE = 1'b1;
    transactions[13].EXPECTED_ERROR = 1'b0;

    transactions[14].ADDR = 32'h80050000;
    transactions[14].DATA = 32'haaaaaaaa;
    transactions[14].STRB = 4'b0;
    transactions[14].WRITE = 1'b0;
    transactions[14].EXPECTED_ERROR = 1'b0;

    transactions[15].ADDR = 32'h80050004;
    transactions[15].DATA = 32'h000000aa;
    transactions[15].STRB = 4'b0;
    transactions[15].WRITE = 1'b0;
    transactions[15].EXPECTED_ERROR = 1'b0;
end

// Initial setup and test case execution block
initial begin
    system_reset_n = 1'b1;  // Ensure DUT starts in reset state
    reset_apb_bus();       // Clear APB bus signals
    dataline_sim_input = 0;
    monitored_data = '0;   // Reset monitored data

    #(0.1);  // Small delay for system stabilization

    if (REG_COUNT == 1) begin
        // Test cases for single register configurations
        testcase_number = 1;
        reset_device_under_test();

        // Execute APB transactions for standard read and write
        execute_apb_transactions(transactions[0]);
        execute_apb_transactions(transactions[1]);

        // Send and monitor signals for module feedback
        data_stream = 32'haaaaaaaa;
        for (current_index = 0; current_index < PIN_COUNT; current_index++) begin
            send_and_monitor_signals(data_stream, ff_inputs[current_index], 1, 0);
        end

        data_stream = 32'h8c37afb0;
        for (current_index = 0; current_index < PIN_COUNT; current_index++) begin
            send_and_monitor_signals(data_stream, module_outputs[current_index * FUNC_COUNT], 0, 0);
        end

        #(SIGNAL_PERIOD);

        // Additional test cases with specific error conditions and PSTRB settings
        testcase_number = 2;
        reset_device_under_test();
        execute_apb_transactions(transactions[2]);
        execute_apb_transactions(transactions[3]);

        data_stream = 32'haaaaaaaa;
        for (current_index = 0; current_index < PIN_COUNT; current_index++) begin
            send_and_monitor_signals(data_stream, ff_inputs[current_index], 1, 3);
        end

        data_stream = 32'h8c37afb0;
        for (current_index = 0; current_index < PIN_COUNT; current_index++) begin
            send_and_monitor_signals(data_stream, module_outputs[current_index * FUNC_COUNT + 3], 0, 3);
        end

        // Tests to check the handling of slave errors and PSTRB effects
        testcase_number = 3;
        reset_device_under_test();
        execute_apb_transactions(transactions[4]);
        execute_apb_transactions(transactions[5]);

        testcase_number = 4;
        reset_device_under_test();
        execute_apb_transactions(transactions[6]);
        execute_apb_transactions(transactions[7]);
    end

    if (REG_COUNT == 2) begin
        // Test cases for dual register configurations
        testcase_number = 5;
        reset_device_under_test();

        // Writing and then reading to test configuration persistence
        execute_apb_transactions(transactions[8]);
        execute_apb_transactions(transactions[9]);
        execute_apb_transactions(transactions[10]);
        execute_apb_transactions(transactions[11]);

        data_stream = 32'haaaaaaaa;
        for (current_index = 0; current_index < PIN_COUNT; current_index++) begin
            send_and_monitor_signals(data_stream, ff_inputs[current_index], 1, 1);
        end

        data_stream = 32'h8c37afb0;
        for (current_index = 0; current_index < PIN_COUNT; current_index++) begin
            send_and_monitor_signals(data_stream, module_outputs[current_index * FUNC_COUNT + 1], 0, 1);
        end

        testcase_number = 6;
        reset_device_under_test();
        execute_apb_transactions(transactions[12]);
        execute_apb_transactions(transactions[13]);
        execute_apb_transactions(transactions[14]);
        execute_apb_transactions(transactions[15]);

        data_stream = 32'haaaaaaaa;
        for (current_index = 0; current_index < PIN_COUNT; current_index++) begin
            send_and_monitor_signals(data_stream, ff_inputs[current_index], 1, 2);
        end

        data_stream = 32'h8c37afb0;
        for (current_index = 0; current_index < PIN_COUNT; current_index++) begin
            send_and_monitor_signals(data_stream, module_outputs[current_index * FUNC_COUNT + 2], 0, 2);
        end
    end

    $stop();  // End simulation after tests
end

endmodule